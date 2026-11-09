/**
 * Script Quantity Copy Service
 *
 * GroupedQuantity is Admin's universal catalog of named "Groups" (per
 * exchange+script) — available to every Master to choose from, not scoped
 * or assigned per master. ScriptQuantity is the actual enforced per-owner
 * limit that trade placement checks against.
 *
 * - Admin creates Master → copy from GroupedQuantity (merges every group;
 *   masters aren't themselves assigned one specific group)
 * - Master creates Sub-Master → copy from parent master's ScriptQuantity
 * - Master creates User → seeded from the specific Group picked per
 *   exchange on the creation form (seedUserScriptQuantityFromGroups) — a
 *   user's assigned Group is also the ceiling any later per-script edit
 *   for that user must respect; raising above it requires switching the
 *   user to a different Group first (reseedUserScriptQuantityForExchange)
 */

const mongoose = require('mongoose');
const ScriptQuantity = require('../models/ScriptQuantity');
const GroupedQuantity = require('../models/GroupedQuantity');
const User = require('../models/User');
const Master = require('../models/Master');

/**
 * Copy GroupedQuantity (global) data into ScriptQuantity for a new master.
 * Called when admin creates the first-level master.
 * @param {string} masterId - The new master's _id
 * @param {object} [session] - Optional mongoose session
 * @param {Array<{exchange_name:string, group_name:string}>} [scriptQuantityGroups] -
 *   explicit group picked per exchange (Master.script_quantity_groups). For any
 *   exchange with an explicit pick, only that group's rows are copied — this is
 *   what makes the master's own group membership trackable, so a later
 *   GroupedQuantity edit can find and cascade to them. Exchanges with no
 *   explicit pick fall back to the old "first group found" behavior, for
 *   backward compatibility with callers that don't pass this yet.
 */
async function copyFromGroupedQuantityToMaster(masterId, session, scriptQuantityGroups) {
  try {
    const picks = new Map((scriptQuantityGroups || []).map(g => [g.exchange_name.toUpperCase(), g.group_name]));

    const docs = [];

    // Explicit per-exchange picks first — only that exchange's chosen group.
    for (const [exchangeName, groupName] of picks) {
      const groupRows = await (session
        ? GroupedQuantity.find({ exchange_name: exchangeName, lot_name: groupName, deleted_at: null }).session(session)
        : GroupedQuantity.find({ exchange_name: exchangeName, lot_name: groupName, deleted_at: null })
      ).lean();
      for (const gq of groupRows) {
        docs.push({
          owner_id: masterId,
          owner_type: 'Master',
          exchange_name: exchangeName,
          script_name: gq.raw_name,
          lot_size: gq.lot_size || 1,
          max_qty: gq.max_qty || 0,
          brk_qty: gq.break_qty || 0,
        });
      }
    }

    // Fallback for exchanges with no explicit pick: old "first group found" behavior.
    const groupedData = await (session
      ? GroupedQuantity.find({ deleted_at: null }).select('exchange_name raw_name max_qty break_qty lot_size').session(session)
      : GroupedQuantity.find({ deleted_at: null }).select('exchange_name raw_name max_qty break_qty lot_size')
    ).lean();
    const seen = new Set();
    for (const gq of groupedData) {
      if (picks.has(gq.exchange_name)) continue; // already handled explicitly above
      // max_qty 0 now means "not tradable" (see tradeController's limit check) —
      // only a group that is explicitly picked may block a script; this
      // "first group found" fallback never copies a 0 (e.g. INDEX ONLY's).
      if (!(Number(gq.max_qty) > 0)) continue;
      const key = `${gq.exchange_name}|${gq.raw_name}`;
      if (seen.has(key)) continue;
      seen.add(key);
      docs.push({
        owner_id: masterId,
        owner_type: 'Master',
        exchange_name: gq.exchange_name,
        script_name: gq.raw_name,
        lot_size: gq.lot_size || 1,
        max_qty: gq.max_qty || 0,
        brk_qty: gq.break_qty || 0,
      });
    }

    if (docs.length > 0) {
      if (session) {
        await ScriptQuantity.insertMany(docs, { session });
      } else {
        await ScriptQuantity.insertMany(docs);
      }
      console.log(`📋 [ScriptQtyCopy] Copied ${docs.length} entries from GroupedQuantity to Master ${masterId}`);
    }
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error copying to master ${masterId}:`, e.message);
  }
}

/**
 * Copy a parent master's ScriptQuantity data to a new sub-master.
 * Called when a master creates a child master.
 * @param {string} parentMasterId - The parent master's _id
 * @param {string} childMasterId - The new child master's _id
 * @param {object} [session] - Optional mongoose session
 */
async function copyFromMasterToSubMaster(parentMasterId, childMasterId, session) {
  try {
    const parentData = await ScriptQuantity.find({
      owner_id: parentMasterId,
      owner_type: 'Master',
      deleted_at: null,
    }).lean();

    if (parentData.length === 0) return;

    const docs = parentData.map(sq => ({
      owner_id: childMasterId,
      owner_type: 'Master',
      exchange_name: sq.exchange_name,
      script_name: sq.script_name,
      lot_size: sq.lot_size,
      max_qty: sq.max_qty,
      brk_qty: sq.brk_qty,
    }));

    if (docs.length > 0) {
      if (session) {
        await ScriptQuantity.insertMany(docs, { session });
      } else {
        await ScriptQuantity.insertMany(docs);
      }
      console.log(`📋 [ScriptQtyCopy] Copied ${docs.length} entries from Master ${parentMasterId} to Sub-Master ${childMasterId}`);
    }
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error copying to sub-master ${childMasterId}:`, e.message);
  }
}

/**
 * Scripts the client's own (direct) master has blocked — max_qty 0 — on these
 * exchanges: exchange -> Map(script -> lot_size). A master's block carries to
 * every client it creates or moves to another group (26 Oct 2026: KK20 had
 * blocked 11 scripts, but a new client would have got them from the group).
 * Only blocks carry — every other limit still comes from the group (masters'
 * own numbers are mostly far below their clients', so a full cap would cut
 * them). Sub-masters and their clients are not touched.
 */
async function masterBlockedScripts(userId, exchangeNames, session) {
  const out = new Map();
  if (!exchangeNames.length) return out;
  const uq = User.findById(userId).select('master_id');
  if (session) uq.session(session);
  const user = await uq.lean();
  if (!user?.master_id) return out;
  const q = ScriptQuantity.find({ owner_id: user.master_id, owner_type: 'Master', exchange_name: { $in: exchangeNames }, max_qty: 0, deleted_at: null })
    .select('exchange_name script_name lot_size');
  if (session) q.session(session);
  for (const r of await q.lean()) {
    if (!out.has(r.exchange_name)) out.set(r.exchange_name, new Map());
    out.get(r.exchange_name).set(r.script_name, r.lot_size || 1);
  }
  return out;
}

/** One exchange's rows with the master's blocks applied; a blocked script the group doesn't list still gets a 0 row (no row = no limit). */
function applyMasterBlocks(docs, userId, exchangeName, blocked) {
  if (!blocked || blocked.size === 0) return docs;
  const seen = new Set();
  for (const d of docs) {
    if (blocked.has(d.script_name)) { d.max_qty = 0; d.brk_qty = 0; seen.add(d.script_name); }
  }
  for (const [script, lotSize] of blocked) {
    if (!seen.has(script)) docs.push({ owner_id: userId, owner_type: 'User', exchange_name: exchangeName, script_name: script, lot_size: lotSize, max_qty: 0, brk_qty: 0 });
  }
  return docs;
}

/**
 * Seeds a new user's ScriptQuantity from the per-exchange "Group" selected
 * at creation (the mobile app's Create User screen: an exchange row, a
 * turnover/lot toggle, and a Group dropdown — `exchanges_allowed[].group_name`).
 *
 * Previously group_name was required by the API, stored on the user
 * record, and then never read again — copyFromMasterToUser always just
 * copied whatever the parent master's CURRENT ScriptQuantity happened to
 * be, so picking a different group in the UI had no effect on the user's
 * actual trading limits at all.
 *
 * GroupedQuantity is Admin's universal set of named groups — available to
 * ANY master to choose from, not scoped or capped per master. A master
 * picks ONE group per exchange for a new user, and that group's values are
 * copied to the user directly, as-is — group definitions themselves can
 * only be created/edited by Admin, never by a master. If a master wants a
 * SPECIFIC user to trade more (or less) than their assigned group allows
 * on a particular script, that's done afterward via the separate Script
 * Qty editing endpoint, not by changing the group.
 *
 * For each exchange the new user is being granted, looks up GroupedQuantity
 * rows for that (exchange_name, lot_name === group_name) pair — that's
 * what a "named group" actually is in this data model — and seeds one
 * ScriptQuantity row per script in that group with the group's own values —
 * except scripts the client's master has blocked (0), which stay 0
 * (masterBlockedScripts).
 *
 * @param {string} userId
 * @param {Array<{exchange_name: string, group_name: string}>} exchangesAllowed
 * @param {object} [session]
 */
async function seedUserScriptQuantityFromGroups(userId, exchangesAllowed, session) {
  try {
    const docs = [];
    const exchangeNames = [...new Set((exchangesAllowed || []).map((ex) => (ex.exchange_name || '').toUpperCase()).filter(Boolean))];
    const blocked = await masterBlockedScripts(userId, exchangeNames, session);

    for (const ex of exchangesAllowed || []) {
      const exchangeName = (ex.exchange_name || '').toUpperCase();
      if (!exchangeName) continue;
      if (!ex.group_name) {
        // No group: nothing from a group, but the master's blocks still apply.
        docs.push(...applyMasterBlocks([], userId, exchangeName, blocked.get(exchangeName)));
        continue;
      }

      const groupRows = await (session
        ? GroupedQuantity.find({ exchange_name: exchangeName, lot_name: ex.group_name, deleted_at: null }).session(session)
        : GroupedQuantity.find({ exchange_name: exchangeName, lot_name: ex.group_name, deleted_at: null })
      ).lean();

      const exDocs = groupRows.map((gq) => ({
        owner_id: userId,
        owner_type: 'User',
        exchange_name: exchangeName,
        script_name: gq.raw_name,
        lot_size: gq.lot_size || 1,
        max_qty: gq.max_qty || 0,
        brk_qty: gq.break_qty || 0,
      }));
      docs.push(...applyMasterBlocks(exDocs, userId, exchangeName, blocked.get(exchangeName)));
    }

    if (docs.length > 0) {
      if (session) {
        await ScriptQuantity.insertMany(docs, { session });
      } else {
        await ScriptQuantity.insertMany(docs);
      }
      console.log(`📋 [ScriptQtyCopy] Seeded ${docs.length} entries for User ${userId} from their assigned groups`);
    }
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error seeding user ${userId} from groups:`, e.message);
  }
}

/**
 * Re-seeds a user's ScriptQuantity for ONE exchange when their assigned
 * Group for that exchange is changed after creation. A master can lower a
 * user's individual script limits within their current group's max, but
 * raising above it requires switching the user to a different (higher)
 * group first — this is what applies that switch: replaces every existing
 * ScriptQuantity row this user has for the given exchange with the new
 * group's values, exactly as if the user were being created fresh with
 * that group (any prior per-script override for this exchange is
 * intentionally discarded, since it belonged to the old group's ceiling).
 *
 * @param {string} userId
 * @param {string} exchangeName
 * @param {string} groupName
 * @param {object} [session]
 */
async function reseedUserScriptQuantityForExchange(userId, exchangeName, groupName, session) {
  // All-or-nothing (owner, 9 Nov 2026): the old rows are removed and the new
  // group's rows added in ONE transaction. Before, the old rows were deleted
  // first with no transaction and errors only logged — a failure (or a group
  // with no scripts) left the client with NO limit rows on that exchange, and
  // a script with no row has no limit at all. A group with no scripts now
  // aborts and keeps the client's current limits.
  // Returns { ok: true, count } or { ok: false, error }.
  const normalizedExchange = String(exchangeName || '').toUpperCase();
  const run = async (s) => {
    const groupRows = await GroupedQuantity.find({ exchange_name: normalizedExchange, lot_name: groupName, deleted_at: null }).session(s).lean();
    if (groupRows.length === 0) throw new Error(`group "${groupName}" has no scripts for ${normalizedExchange}`);

    const deleteQuery = { owner_id: userId, owner_type: 'User', exchange_name: normalizedExchange, deleted_at: null };
    await ScriptQuantity.updateMany(deleteQuery, { $set: { deleted_at: new Date() } }, { session: s });

    // The master's blocks apply on top of the new group (masterBlockedScripts).
    const blocked = (await masterBlockedScripts(userId, [normalizedExchange], s)).get(normalizedExchange);
    const docs = applyMasterBlocks(groupRows.map(gq => ({
      owner_id: userId,
      owner_type: 'User',
      exchange_name: normalizedExchange,
      script_name: gq.raw_name,
      lot_size: gq.lot_size || 1,
      max_qty: gq.max_qty || 0,
      brk_qty: gq.break_qty || 0,
    })), userId, normalizedExchange, blocked);
    if (docs.length === 0) throw new Error(`group "${groupName}" gave no rows for ${normalizedExchange}`);
    await ScriptQuantity.insertMany(docs, { session: s });
    return docs.length;
  };
  try {
    let count = 0;
    if (session) {
      count = await run(session);
    } else {
      const own = await mongoose.startSession();
      try {
        await own.withTransaction(async () => { count = await run(own); });
      } finally {
        await own.endSession();
      }
    }
    console.log(`📋 [ScriptQtyCopy] Re-seeded ${count} entries for User ${userId} on ${normalizedExchange} from group "${groupName}"`);
    return { ok: true, count };
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Re-seed refused for user ${userId} on ${normalizedExchange} (group "${groupName}") — current limits kept:`, e.message);
    return { ok: false, error: e.message };
  }
}

/**
 * After a client's record was saved with new group names: re-seed each
 * changed exchange (all-or-nothing each). A switch that fails is put back on
 * the record so it matches the limits he really has — the previous group,
 * or, for an exchange he didn't have before (no limits to keep), the
 * exchange is left switched off instead of open without limits. A retry then
 * sees the change again. Returns the failures [{ exchange_name, group_name,
 * error, disabled }] — empty when every switch went through.
 */
async function applyUserGroupChanges(user, groupChanges, previousGroups) {
  const failed = [];
  for (const ex of groupChanges) {
    const r = await reseedUserScriptQuantityForExchange(String(user._id), ex.exchange_name, ex.group_name);
    if (r.ok) continue;
    const old = previousGroups.get(ex.exchange_name);
    const set = old
      ? { 'exchanges_allowed.$.group_name': old }
      : { 'exchanges_allowed.$.turnover': false, 'exchanges_allowed.$.lot': false };
    await User.updateOne({ _id: user._id, 'exchanges_allowed.exchange_name': ex.exchange_name }, { $set: set });
    failed.push({ exchange_name: ex.exchange_name, group_name: ex.group_name, error: r.error, disabled: !old });
  }
  return failed;
}

/** A clear message for a client edit whose group switch(es) did not go through. */
function groupChangeFailureMessage(failed) {
  const parts = failed.map((f) => `${f.exchange_name === 'INDICES' ? 'GLOBAL' : f.exchange_name} → "${f.group_name}" (${f.error})${f.disabled ? ' — this exchange was left switched off' : ' — previous group and limits kept'}`);
  return `Other changes were saved, but the group change did not go through: ${parts.join('; ')}. Please try again.`;
}

/** True when the group has at least one script for this exchange (a client can be switched to it). */
async function groupHasScripts(exchangeName, groupName) {
  return Boolean(await GroupedQuantity.exists({ exchange_name: String(exchangeName || '').toUpperCase(), lot_name: groupName, deleted_at: null }));
}

/**
 * Re-seeds a MASTER's ScriptQuantity for ONE exchange when their assigned
 * Group for that exchange is changed after creation — the Master-side
 * mirror of reseedUserScriptQuantityForExchange above. Also updates
 * Master.script_quantity_groups itself so the new membership is recorded
 * (without this, a later GroupedQuantity edit wouldn't find this master).
 * @param {string} masterId
 * @param {string} exchangeName
 * @param {string} groupName
 * @param {object} [session]
 */
async function reseedMasterScriptQuantityForExchange(masterId, exchangeName, groupName, session) {
  // All-or-nothing (owner, 9 Nov 2026), like the client's group switch: the
  // old rows go and the new group's arrive in ONE transaction, the master's
  // own blocks (max 0) are kept, and a group with no scripts is refused —
  // it used to delete everything first, swallow errors, and could leave the
  // master with no rows (no row = no limit). Returns { ok, count } / { ok:false, error }.
  const normalizedExchange = String(exchangeName || '').toUpperCase();
  const run = async (s) => {
    const groupRows = await GroupedQuantity.find({ exchange_name: normalizedExchange, lot_name: groupName, deleted_at: null }).session(s).lean();
    if (groupRows.length === 0) throw new Error(`group "${groupName}" has no scripts for ${normalizedExchange}`);
    const blocked = new Map((await ScriptQuantity.find({ owner_id: masterId, owner_type: 'Master', exchange_name: normalizedExchange, max_qty: 0, deleted_at: null })
      .select('script_name lot_size').session(s).lean()).map((r) => [r.script_name, r.lot_size || 1]));
    await ScriptQuantity.updateMany({ owner_id: masterId, owner_type: 'Master', exchange_name: normalizedExchange, deleted_at: null }, { $set: { deleted_at: new Date() } }, { session: s });
    await Master.updateOne({ _id: masterId }, { $pull: { script_quantity_groups: { exchange_name: normalizedExchange } } }, { session: s });
    await Master.updateOne({ _id: masterId }, { $push: { script_quantity_groups: { exchange_name: normalizedExchange, group_name: groupName } } }, { session: s });
    const docs = groupRows.map((gq) => ({
      owner_id: masterId,
      owner_type: 'Master',
      exchange_name: normalizedExchange,
      script_name: gq.raw_name,
      lot_size: gq.lot_size || 1,
      max_qty: blocked.has(gq.raw_name) ? 0 : (gq.max_qty || 0),
      brk_qty: blocked.has(gq.raw_name) ? 0 : (gq.break_qty || 0),
    }));
    const listed = new Set(docs.map((d) => d.script_name));
    for (const [script, lotSize] of blocked) {
      if (!listed.has(script)) docs.push({ owner_id: masterId, owner_type: 'Master', exchange_name: normalizedExchange, script_name: script, lot_size: lotSize, max_qty: 0, brk_qty: 0 });
    }
    await ScriptQuantity.insertMany(docs, { session: s });
    return docs.length;
  };
  try {
    let count = 0;
    if (session) {
      count = await run(session);
    } else {
      const own = await mongoose.startSession();
      try {
        await own.withTransaction(async () => { count = await run(own); });
      } finally {
        await own.endSession();
      }
    }
    console.log(`📋 [ScriptQtyCopy] Re-seeded ${count} entries for Master ${masterId} on ${normalizedExchange} from group "${groupName}" (own blocks kept)`);
    return { ok: true, count };
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Master re-seed refused for ${masterId} on ${normalizedExchange} (group "${groupName}") — current limits kept:`, e.message);
    return { ok: false, error: e.message };
  }
}

/**
 * Cascade a master's ScriptQuantity update to all direct users.
 * Called when admin/master updates ScriptQuantity on a master's profile.
 * Only updates direct users (not sub-masters' users).
 * @param {string} masterId - The master whose data was updated
 * @param {string} exchangeName - The exchange that was updated
 * @param {string} scriptName - The script/raw_name that was updated
 * @param {object} newValues - { max_qty, brk_qty, lot_size }
 */
async function cascadeToDirectUsers(masterId, exchangeName, scriptName, newValues) {
  try {
    // Find all direct users of this master
    const directUsers = await User.find({
      master_id: masterId,
      deleted_at: null,
    }).select('_id').lean();

    if (directUsers.length === 0) return;

    const userIds = directUsers.map(u => u._id);

    // Update all matching ScriptQuantity entries for these users
    const result = await ScriptQuantity.updateMany(
      {
        owner_id: { $in: userIds },
        owner_type: 'User',
        exchange_name: exchangeName.toUpperCase(),
        script_name: scriptName,
        deleted_at: null,
      },
      {
        $set: {
          max_qty: newValues.max_qty,
          brk_qty: newValues.brk_qty,
          ...(newValues.lot_size !== undefined ? { lot_size: newValues.lot_size } : {}),
          updated_at: new Date(),
        },
      }
    );

    console.log(`📋 [ScriptQtyCopy] Cascaded ${scriptName}/${exchangeName} update to ${result.modifiedCount}/${directUsers.length} direct users of Master ${masterId}`);
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error cascading to users:`, e.message);
  }
}

/**
 * Cascade a NEW script entry to all direct users of a master.
 * Called when admin/master creates a new ScriptQuantity for a master.
 * Upserts the record for each user so existing ones are updated, new ones are created.
 * @param {string} masterId
 * @param {string} exchangeName
 * @param {string} scriptName
 * @param {object} values - { lot_size, max_qty, brk_qty }
 */
async function cascadeNewScriptToUsers(masterId, exchangeName, scriptName, values) {
  try {
    const directUsers = await User.find({
      master_id: masterId,
      deleted_at: null,
    }).select('_id').lean();

    if (directUsers.length === 0) return;

    const normalizedExchange = exchangeName.toUpperCase();
    const now = new Date();

    const bulkOps = directUsers.map(u => ({
      updateOne: {
        filter: {
          owner_id: u._id,
          owner_type: 'User',
          exchange_name: normalizedExchange,
          script_name: scriptName,
          deleted_at: null,
        },
        update: {
          $set: {
            lot_size: values.lot_size,
            max_qty: values.max_qty,
            brk_qty: values.brk_qty,
            updated_at: now,
            deleted_at: null,
          },
          $setOnInsert: {
            owner_id: u._id,
            owner_type: 'User',
            exchange_name: normalizedExchange,
            script_name: scriptName,
            created_at: now,
          },
        },
        upsert: true,
      },
    }));

    const result = await ScriptQuantity.bulkWrite(bulkOps);
    console.log(`📋 [ScriptQtyCopy] Cascaded new script ${scriptName}/${normalizedExchange} to ${directUsers.length} users of Master ${masterId} (upserted: ${result.upsertedCount}, modified: ${result.modifiedCount})`);
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error cascading new script to users:`, e.message);
  }
}

/**
 * Cascade a soft-delete to all direct users of a master for a specific script.
 * Called when admin/master deletes a ScriptQuantity on a master.
 * @param {string} masterId
 * @param {string} exchangeName
 * @param {string} scriptName
 */
async function cascadeDeleteScriptToUsers(masterId, exchangeName, scriptName) {
  try {
    const directUsers = await User.find({
      master_id: masterId,
      deleted_at: null,
    }).select('_id').lean();

    if (directUsers.length === 0) return;

    const userIds = directUsers.map(u => u._id);
    const normalizedExchange = exchangeName.toUpperCase();

    const result = await ScriptQuantity.updateMany(
      {
        owner_id: { $in: userIds },
        owner_type: 'User',
        exchange_name: normalizedExchange,
        script_name: scriptName,
        deleted_at: null,
      },
      { $set: { deleted_at: new Date() } }
    );

    console.log(`📋 [ScriptQtyCopy] Cascade-deleted ${scriptName}/${normalizedExchange} for ${result.modifiedCount}/${directUsers.length} users of Master ${masterId}`);
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error cascading delete to users:`, e.message);
  }
}

/**
 * Cascade a NEW script from Admin (global) to all Masters and their direct users.
 * Called when admin creates a ScriptQuantity at the global level.
 * @param {string} exchangeName
 * @param {string} scriptName
 * @param {object} values - { lot_size, max_qty, brk_qty }
 */
/**
 * Cascade a NEW script from Admin to their own Masters and those Masters' users.
 * Called when admin creates/updates a ScriptQuantity at their level.
 * @param {string} exchangeName
 * @param {string} scriptName
 * @param {object} values - { lot_size, max_qty, brk_qty }
 * @param {string} [adminId] - The admin's ID to scope cascade to their hierarchy only
 */
async function cascadeNewScriptGlobally(exchangeName, scriptName, values, adminId) {
  try {
    const Master = require('../models/Master');
    
    // If adminId is provided, only cascade to that admin's masters
    const masterFilter = { deleted_at: null };
    if (adminId) {
      masterFilter.admin_id = adminId;
    }
    const allMasters = await Master.find(masterFilter).select('_id').lean();

    if (allMasters.length === 0) return;

    const normalizedExchange = exchangeName.toUpperCase();
    const now = new Date();

    const masterIds = allMasters.map(m => m._id);

    // First: updateMany to update ALL existing master records (handles duplicates)
    await ScriptQuantity.updateMany(
      {
        owner_id: { $in: masterIds },
        owner_type: 'Master',
        exchange_name: normalizedExchange,
        script_name: scriptName,
        deleted_at: null,
      },
      { $set: { lot_size: values.lot_size, max_qty: values.max_qty, brk_qty: values.brk_qty, updated_at: now } }
    );

    // Then: upsert for masters who don't have a record yet
    const masterBulkOps = allMasters.map(m => ({
      updateOne: {
        filter: {
          owner_id: m._id,
          owner_type: 'Master',
          exchange_name: normalizedExchange,
          script_name: scriptName,
          deleted_at: null,
        },
        update: {
          $set: { lot_size: values.lot_size, max_qty: values.max_qty, brk_qty: values.brk_qty, updated_at: now, deleted_at: null },
          $setOnInsert: { owner_id: m._id, owner_type: 'Master', exchange_name: normalizedExchange, script_name: scriptName, created_at: now },
        },
        upsert: true,
      },
    }));
    await ScriptQuantity.bulkWrite(masterBulkOps);

    // Same for users under these masters
    const allUsers = await User.find({ master_id: { $in: masterIds }, deleted_at: null }).select('_id').lean();

    if (allUsers.length > 0) {
      const userIds = allUsers.map(u => u._id);

      // Update ALL existing user records for this script (handles duplicates)
      await ScriptQuantity.updateMany(
        {
          owner_id: { $in: userIds },
          owner_type: 'User',
          exchange_name: normalizedExchange,
          script_name: scriptName,
          deleted_at: null,
        },
        { $set: { lot_size: values.lot_size, max_qty: values.max_qty, brk_qty: values.brk_qty, updated_at: now } }
      );

      // Upsert for users who don't have a record yet
      const userBulkOps = allUsers.map(u => ({
        updateOne: {
          filter: {
            owner_id: u._id,
            owner_type: 'User',
            exchange_name: normalizedExchange,
            script_name: scriptName,
            deleted_at: null,
          },
          update: {
            $set: { lot_size: values.lot_size, max_qty: values.max_qty, brk_qty: values.brk_qty, updated_at: now, deleted_at: null },
            $setOnInsert: { owner_id: u._id, owner_type: 'User', exchange_name: normalizedExchange, script_name: scriptName, created_at: now },
          },
          upsert: true,
        },
      }));
      await ScriptQuantity.bulkWrite(userBulkOps);
    }

    console.log(`📋 [ScriptQtyCopy] Globally cascaded new script ${scriptName}/${normalizedExchange} to ${allMasters.length} masters and ${allUsers.length} users`);
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error globally cascading new script:`, e.message);
  }
}

/**
 * Cascade a soft-delete to all Masters and their users for a specific script.
 * Called when admin deletes a global-level ScriptQuantity.
 * @param {string} exchangeName
 * @param {string} scriptName
 * @param {string} [adminId] - The admin's ID to scope cascade to their hierarchy only
 */
async function cascadeDeleteScriptGlobally(exchangeName, scriptName, adminId) {
  try {
    const Master = require('../models/Master');
    const normalizedExchange = exchangeName.toUpperCase();
    const now = new Date();

    // Find only this admin's masters
    const masterFilter = { deleted_at: null };
    if (adminId) {
      masterFilter.admin_id = adminId;
    }
    const masters = await Master.find(masterFilter).select('_id').lean();
    const masterIds = masters.map(m => m._id);

    // Delete for masters
    await ScriptQuantity.updateMany(
      {
        owner_id: { $in: masterIds },
        owner_type: 'Master',
        exchange_name: normalizedExchange,
        script_name: scriptName,
        deleted_at: null,
      },
      { $set: { deleted_at: now } }
    );

    // Delete for users under those masters
    const allUsers = await User.find({ master_id: { $in: masterIds }, deleted_at: null }).select('_id').lean();
    if (allUsers.length > 0) {
      const userIds = allUsers.map(u => u._id);
      await ScriptQuantity.updateMany(
        {
          owner_id: { $in: userIds },
          owner_type: 'User',
          exchange_name: normalizedExchange,
          script_name: scriptName,
          deleted_at: null,
        },
        { $set: { deleted_at: now } }
      );
    }

    console.log(`📋 [ScriptQtyCopy] Deleted script ${scriptName}/${normalizedExchange} for ${masterIds.length} masters and ${allUsers.length} users`);
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error cascading delete:`, e.message);
  }
}


/**
 * Cascade NEW scripts from Master to their direct users in bulk.
 * @param {string} masterId
 * @param {string} exchangeName
 * @param {Array} scripts - [{ script_name, max_qty, brk_qty, lot_size }]
 */
async function bulkCascadeNewScriptsToUsers(masterId, exchangeName, scripts) {
  try {
    const directUsers = await User.find({ master_id: masterId, deleted_at: null }).select('_id').lean();
    if (directUsers.length === 0) return;

    const userIds = directUsers.map(u => u._id);
    const normalizedExchange = exchangeName.toUpperCase();
    const now = new Date();

    const bulkOps = [];
    for (const u of userIds) {
      for (const s of scripts) {
        bulkOps.push({
          updateOne: {
            filter: {
              owner_id: u,
              owner_type: 'User',
              exchange_name: normalizedExchange,
              script_name: s.script_name,
              deleted_at: null,
            },
            update: {
              $set: { lot_size: s.lot_size, max_qty: s.max_qty, brk_qty: s.brk_qty, updated_at: now, deleted_at: null },
              $setOnInsert: { owner_id: u, owner_type: 'User', exchange_name: normalizedExchange, script_name: s.script_name, created_at: now },
            },
            upsert: true,
          }
        });
      }
    }

    if (bulkOps.length > 0) {
      const result = await ScriptQuantity.bulkWrite(bulkOps);
      console.log(`📋 [ScriptQtyCopy] Bulk cascaded ${scripts.length} scripts for ${normalizedExchange} to ${userIds.length} users (upserted: ${result.upsertedCount}, modified: ${result.modifiedCount})`);
    }
  } catch (e) {
    console.error(`❌ [ScriptQtyCopy] Error bulk cascading new scripts:`, e.message);
  }
}

/**
 * Cascade a GroupedQuantity (a "Group" itself, e.g. NFO-FUT "Lot 1") create/
 * update to every Master and User currently on that group for that
 * exchange — the piece that was previously missing entirely. Editing a
 * Group in the admin catalog only ever touched that one catalog document;
 * nothing pushed the new value out to whoever was actually using it. This
 * finds every account whose group membership (User.exchanges_allowed[]
 * .group_name, or Master.script_quantity_groups[].group_name) matches the
 * edited group, and overwrites their ScriptQuantity row for that script to
 * the group's new values — the same $set+upsert pattern the direct
 * Script-Quantity cascades above already use, just keyed by group
 * membership instead of parent/child relationship. Because the ceiling
 * check in adminController.js's create/updateScriptQuantity already reads
 * the group live, this is also what makes the group a real, enforced
 * ceiling: after this runs, nobody's stored value can be above it (a
 * lower-value push here can only ever bring an existing row down to match,
 * never leave it stranded above the new ceiling).
 * @param {string} exchangeName
 * @param {string} lotName - the Group's lot_name
 * @param {string} rawName - the Group's raw_name (== ScriptQuantity.script_name)
 * @param {{max_qty:number, brk_qty:number, lot_size?:number}} newValues
 */
async function cascadeGroupedQuantityUpdate(exchangeName, lotName, rawName, newValues, groupOldMax = null) {
  // Owner, 9 Nov 2026 — the group sets every member's limit (that is how a
  // limit is lowered for everyone on it), with the SAME rule as joining the
  // group: a script the client's own master has blocked (max 0) stays 0
  // (masterBlockedScripts / applyMasterBlocks). Errors are no longer
  // swallowed — the caller reports them (the group itself is already saved).
  const normalizedExchange = exchangeName.toUpperCase();
  const now = new Date();

  const [users, masters] = await Promise.all([
    User.find({
      deleted_at: null,
      exchanges_allowed: { $elemMatch: { exchange_name: normalizedExchange, group_name: lotName } },
    }).select('_id master_id').lean(),
    Master.find({
      deleted_at: null,
      script_quantity_groups: { $elemMatch: { exchange_name: normalizedExchange, group_name: lotName } },
    }).select('_id').lean(),
  ]);

  // Masters on the group first. A master's own block (a 0 the group did not
  // give him: the group's previous value was not 0, or the group had no such
  // script) is kept, like on joining. When the group turns a master's script
  // blocked / unblocked, his direct clients follow (cascadeMasterRowChange).
  const masterRows = masters.length
    ? await ScriptQuantity.find({ owner_id: { $in: masters.map((m) => m._id) }, owner_type: 'Master', exchange_name: normalizedExchange, script_name: rawName, deleted_at: null }).select('owner_id max_qty').lean()
    : [];
  const masterMax = new Map(masterRows.map((r) => [String(r.owner_id), r.max_qty]));
  const masterOps = [];
  const blockChanges = [];
  let mastersKeptBlocked = 0;
  for (const m of masters) {
    const cur = masterMax.has(String(m._id)) ? masterMax.get(String(m._id)) : null;
    if (cur === 0 && groupOldMax !== 0) { mastersKeptBlocked++; continue; }
    masterOps.push({
      updateOne: {
        filter: { owner_id: m._id, owner_type: 'Master', exchange_name: normalizedExchange, script_name: rawName, deleted_at: null },
        update: {
          $set: { max_qty: newValues.max_qty, brk_qty: newValues.brk_qty, ...(newValues.lot_size !== undefined ? { lot_size: newValues.lot_size } : {}), updated_at: now },
          $setOnInsert: { owner_id: m._id, owner_type: 'Master', exchange_name: normalizedExchange, script_name: rawName, created_at: now },
        },
        upsert: true,
      },
    });
    if ((cur === 0) !== (Number(newValues.max_qty) === 0)) blockChanges.push([String(m._id), cur, Number(newValues.max_qty)]);
  }
  if (masterOps.length) await ScriptQuantity.bulkWrite(masterOps, { ordered: false });
  for (const [mid, oldMax, newMax] of blockChanges) {
    await cascadeMasterRowChange(mid, normalizedExchange, rawName, oldMax, newMax, newValues.lot_size);
  }

  // Clients on the group — read AFTER the masters were written.
  const blockingMasters = await mastersBlockingScript(users.map((u) => u.master_id), normalizedExchange, rawName);

  const bulkOps = [];
  let keptBlocked = 0;
  for (const u of users) {
    const blocked = blockingMasters.has(String(u.master_id));
    if (blocked) keptBlocked++;
    const values = blocked ? { max_qty: 0, brk_qty: 0 } : { max_qty: newValues.max_qty, brk_qty: newValues.brk_qty };
    bulkOps.push({
      updateOne: {
        filter: { owner_id: u._id, owner_type: 'User', exchange_name: normalizedExchange, script_name: rawName, deleted_at: null },
        update: {
          $set: { ...values, ...(newValues.lot_size !== undefined ? { lot_size: newValues.lot_size } : {}), updated_at: now },
          $setOnInsert: { owner_id: u._id, owner_type: 'User', exchange_name: normalizedExchange, script_name: rawName, created_at: now },
        },
        upsert: true,
      },
    });
  }
  if (bulkOps.length > 0) await ScriptQuantity.bulkWrite(bulkOps, { ordered: false });
  console.log(`📋 [ScriptQtyCopy] Cascaded group "${lotName}"/${normalizedExchange}/${rawName} update to ${users.length} user(s) (${keptBlocked} kept blocked by their master) + ${masters.length} master(s) (${mastersKeptBlocked} kept their own block)`);
  return { users: users.length, masters: masters.length, keptBlocked, mastersKeptBlocked };
}

/**
 * A script REMOVED from a group (owner, 9 Nov 2026 — same rule as joining a
 * group): every member loses the row the group gave him, except a client
 * whose own master has blocked the script, who keeps (or gets) a 0 row.
 * Masters on the group lose the row too. Errors reach the caller.
 */
async function removeGroupScriptFromMembers(exchangeName, lotName, rawName, groupOldMax = null) {
  const normalizedExchange = exchangeName.toUpperCase();
  const now = new Date();
  const [users, masters] = await Promise.all([
    User.find({ deleted_at: null, exchanges_allowed: { $elemMatch: { exchange_name: normalizedExchange, group_name: lotName } } }).select('_id master_id').lean(),
    Master.find({ deleted_at: null, script_quantity_groups: { $elemMatch: { exchange_name: normalizedExchange, group_name: lotName } } }).select('_id').lean(),
  ]);
  // Masters first: the row the group gave goes; a master's own block (a 0
  // the group didn't give — the group's value was not 0) stays, like on
  // joining. A block that came from the group and now goes reaches his clients.
  let mastersKeptBlocked = 0;
  if (masters.length) {
    const rows = await ScriptQuantity.find({ owner_id: { $in: masters.map((m) => m._id) }, owner_type: 'Master', exchange_name: normalizedExchange, script_name: rawName, deleted_at: null }).select('owner_id max_qty lot_size').lean();
    const drop = rows.filter((r) => !(r.max_qty === 0 && groupOldMax !== 0));
    mastersKeptBlocked = rows.length - drop.length;
    if (drop.length) await ScriptQuantity.updateMany({ _id: { $in: drop.map((r) => r._id) } }, { $set: { deleted_at: now } });
    for (const r of drop.filter((x) => x.max_qty === 0)) {
      await cascadeMasterRowChange(String(r.owner_id), normalizedExchange, rawName, 0, null, r.lot_size);
    }
  }

  const blockingMasters = await mastersBlockingScript(users.map((u) => u.master_id), normalizedExchange, rawName);
  const blockedUsers = users.filter((u) => blockingMasters.has(String(u.master_id))).map((u) => u._id);
  const freeUsers = users.filter((u) => !blockingMasters.has(String(u.master_id))).map((u) => u._id);
  const ops = [];
  if (freeUsers.length) {
    ops.push({ updateMany: { filter: { owner_id: { $in: freeUsers }, owner_type: 'User', exchange_name: normalizedExchange, script_name: rawName, deleted_at: null }, update: { $set: { deleted_at: now } } } });
  }
  for (const uid of blockedUsers) {
    ops.push({
      updateOne: {
        filter: { owner_id: uid, owner_type: 'User', exchange_name: normalizedExchange, script_name: rawName, deleted_at: null },
        update: { $set: { max_qty: 0, brk_qty: 0, updated_at: now }, $setOnInsert: { owner_id: uid, owner_type: 'User', exchange_name: normalizedExchange, script_name: rawName, lot_size: 1, created_at: now } },
        upsert: true,
      },
    });
  }
  if (ops.length) await ScriptQuantity.bulkWrite(ops, { ordered: false });
  console.log(`📋 [ScriptQtyCopy] Group "${lotName}"/${normalizedExchange}: removed ${rawName} from ${freeUsers.length} user(s) + ${masters.length} master(s); ${blockedUsers.length} user(s) kept blocked by their master, ${mastersKeptBlocked} master(s) kept their own block`);
  return { users: users.length, masters: masters.length, keptBlocked: blockedUsers.length, mastersKeptBlocked };
}

/** The masters (of the given ids) that have this script blocked (max 0) on this exchange. */
async function mastersBlockingScript(masterIds, exchangeName, scriptName, session = null) {
  const ids = [...new Set((masterIds || []).filter(Boolean).map(String))];
  if (!ids.length) return new Set();
  const q = ScriptQuantity.find({ owner_id: { $in: ids }, owner_type: 'Master', exchange_name: exchangeName, script_name: scriptName, max_qty: 0, deleted_at: null }).select('owner_id');
  if (session) q.session(session);
  return new Set((await q.lean()).map((r) => String(r.owner_id)));
}

/**
 * A master's OWN script row changed (owner, 9 Nov 2026 — same rule as joining
 * a group: from his master a client only takes BLOCKS; every other limit comes
 * from the client's own group).
 *  - blocked now (max 0, wasn't): his direct clients get 0 for that script;
 *  - unblocked (was 0, now another value, or the row was deleted): his direct
 *    clients that sit at 0 for it go back to their group's value, or lose the
 *    row when their group doesn't list the script — exactly what joining gives;
 *  - any other change: clients untouched (it used to overwrite them all).
 * @param {number|null} oldMax  the master's max before (null = had no row)
 * @param {number|null} newMax  the master's max after (null = row deleted)
 */
async function cascadeMasterRowChange(masterId, exchangeName, scriptName, oldMax, newMax, lotSize) {
  const ex = String(exchangeName).toUpperCase();
  const wasBlocked = oldMax === 0;
  const isBlocked = newMax === 0;
  if (wasBlocked === isBlocked) return { action: 'none', users: 0 };
  const users = await User.find({ master_id: masterId, deleted_at: null }).select('_id exchanges_allowed').lean();
  if (!users.length) return { action: isBlocked ? 'block' : 'unblock', users: 0 };
  const now = new Date();
  const ops = [];
  if (isBlocked) {
    for (const u of users) {
      ops.push({
        updateOne: {
          filter: { owner_id: u._id, owner_type: 'User', exchange_name: ex, script_name: scriptName, deleted_at: null },
          update: { $set: { max_qty: 0, brk_qty: 0, updated_at: now }, $setOnInsert: { owner_id: u._id, owner_type: 'User', exchange_name: ex, script_name: scriptName, lot_size: lotSize || 1, created_at: now } },
          upsert: true,
        },
      });
    }
  } else {
    const groupOf = (u) => (u.exchanges_allowed || []).find((e) => String(e.exchange_name).toUpperCase() === ex)?.group_name || null;
    const groups = [...new Set(users.map(groupOf).filter(Boolean))];
    const groupRows = groups.length
      ? await GroupedQuantity.find({ exchange_name: ex, lot_name: { $in: groups }, raw_name: scriptName, deleted_at: null }).lean()
      : [];
    const byGroup = new Map(groupRows.map((g) => [g.lot_name, g]));
    for (const u of users) {
      const g = byGroup.get(groupOf(u));
      const filter = { owner_id: u._id, owner_type: 'User', exchange_name: ex, script_name: scriptName, max_qty: 0, deleted_at: null };
      ops.push(g
        ? { updateOne: { filter, update: { $set: { max_qty: g.max_qty || 0, brk_qty: g.break_qty || 0, lot_size: g.lot_size || lotSize || 1, updated_at: now } } } }
        : { updateOne: { filter, update: { $set: { deleted_at: now } } } });
    }
  }
  const result = await ScriptQuantity.bulkWrite(ops, { ordered: false });
  console.log(`📋 [ScriptQtyCopy] Master ${masterId} ${isBlocked ? 'blocked' : 'unblocked'} ${scriptName}/${ex}: ${result.modifiedCount + result.upsertedCount} client row(s) changed`);
  return { action: isBlocked ? 'block' : 'unblock', users: result.modifiedCount + result.upsertedCount };
}

/**
 * Admin CREATES platform script rows (single or bulk): every master of that
 * admin and their direct clients get the row ONLY where they have none —
 * an existing limit is never overwritten (owner, 9 Nov 2026: a "create" used
 * to reset every account on the exchange, one script at a time).
 * @param {Array<{script_name:string, lot_size:number, max_qty:number, brk_qty:number}>} scripts
 */
async function fillMissingScriptsGlobally(exchangeName, scripts, adminId) {
  const ex = String(exchangeName).toUpperCase();
  const masterFilter = { deleted_at: null };
  if (adminId) masterFilter.admin_id = adminId;
  const masters = await Master.find(masterFilter).select('_id').lean();
  if (!masters.length || !scripts.length) return { masters: masters.length, users: 0, inserted: 0 };
  const users = await User.find({ master_id: { $in: masters.map((m) => m._id) }, deleted_at: null }).select('_id').lean();
  const now = new Date();
  const owners = [...masters.map((m) => [m._id, 'Master']), ...users.map((u) => [u._id, 'User'])];
  let inserted = 0;
  const CHUNK = 5000;
  let ops = [];
  const flush = async () => {
    if (!ops.length) return;
    const r = await ScriptQuantity.bulkWrite(ops, { ordered: false });
    inserted += r.upsertedCount;
    ops = [];
  };
  for (const [ownerId, ownerType] of owners) {
    for (const sc of scripts) {
      ops.push({
        updateOne: {
          filter: { owner_id: ownerId, owner_type: ownerType, exchange_name: ex, script_name: sc.script_name, deleted_at: null },
          update: { $setOnInsert: { owner_id: ownerId, owner_type: ownerType, exchange_name: ex, script_name: sc.script_name, lot_size: sc.lot_size || 1, max_qty: sc.max_qty, brk_qty: sc.brk_qty, created_at: now, deleted_at: null } },
          upsert: true,
        },
      });
      if (ops.length >= CHUNK) await flush();
    }
  }
  await flush();
  console.log(`📋 [ScriptQtyCopy] Filled ${inserted} missing row(s) for ${scripts.length} script(s) on ${ex} across ${masters.length} masters + ${users.length} users (existing limits untouched)`);
  return { masters: masters.length, users: users.length, inserted };
}

// Is `groupName` one this master is allowed to draw from for `exchangeName`
// — either for their own script_quantity_groups pick, or for a group_name
// they hand a client/sub-master? An exchange with no entry (or an empty
// group_names[]) in allotted_script_quantity_groups is unrestricted, so
// every master that existed before this field shipped keeps working as-is.
function isGroupAllotted(master, exchangeName, groupName) {
  const normalizedExchange = String(exchangeName).toUpperCase();
  const allotted = (master && master.allotted_script_quantity_groups) || [];
  const forExchange = allotted.find(a => a.exchange_name === normalizedExchange);
  if (!forExchange || !Array.isArray(forExchange.group_names) || forExchange.group_names.length === 0) {
    return true;
  }
  return forExchange.group_names.includes(groupName);
}

module.exports = {
  copyFromGroupedQuantityToMaster,
  copyFromMasterToSubMaster,
  seedUserScriptQuantityFromGroups,
  reseedUserScriptQuantityForExchange,
  groupHasScripts,
  applyUserGroupChanges,
  groupChangeFailureMessage,
  masterBlockedScripts,
  reseedMasterScriptQuantityForExchange,
  cascadeToDirectUsers,
  cascadeNewScriptToUsers,
  cascadeDeleteScriptToUsers,
  cascadeNewScriptGlobally,
  cascadeDeleteScriptGlobally,
  bulkCascadeNewScriptsToUsers,
  cascadeGroupedQuantityUpdate,
  removeGroupScriptFromMembers,
  mastersBlockingScript,
  cascadeMasterRowChange,
  fillMissingScriptsGlobally,
  isGroupAllotted,
};
