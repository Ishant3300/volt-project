const User = require('../models/User');
const GroupedQuantity = require('../models/GroupedQuantity');
const KiteInstrument = require('../models/KiteInstrument');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');
const { withoutNonTrading } = require('../utils/hideNonTrading');
const { categoryForNfoScript } = require('../constants/nfoIndexUnderlyings');

/**
 * ScriptQuantity.owner_id can be a User._id or a Master._id (Admin-owned
 * global rows use a fixed owner_id too, but those are never gated behind
 * this check since only a master calls it). Resolves it to the master_id
 * whose subtree the record actually belongs to, so a caller's own subtree
 * (getAllSubMasterIds) can be checked against it — same pattern already
 * used for BrokerageSettings ownership in adminController.js.
 */
async function resolveScriptQuantityOwnerMasterId(ownerId) {
  if (!ownerId) return null;
  const owner = await User.findById(ownerId).select('master_id').lean();
  if (owner) return owner.master_id?.toString() || null;
  return ownerId.toString(); // not a User — assume Master, id is its own subtree root
}

// Get lot names by exchange
const getLotNamesByExchange = async (req, res) => {
  try {
    const { exchange_name } = req.params;

    if (!exchange_name) {
      return res.status(400).json({
        success: false,
        message: 'Exchange name is required',
        data: null
      });
    }

    let lotNames = await GroupedQuantity.distinct('lot_name', {
      exchange_name: exchange_name.toUpperCase(),
      deleted_at: null
    });

    // A master only ever sees the groups admin actually allotted them for
    // this exchange — same ceiling enforced server-side on create/update,
    // surfaced here so their own dropdown doesn't even offer the rest.
    // Admin callers see every group, unrestricted.
    // ?for_master_id=: the groups THAT master may hand out (an upper master
    // or admin editing a sub-master's client — the server checks the client's
    // own master's allotment on save). Must be in the caller's tree (9 Nov 2026).
    const forMasterId = req.query.for_master_id ? String(req.query.for_master_id) : null;
    if (forMasterId && req.master && forMasterId !== String(req.master.id)) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      if (!(await getAllSubMasterIds(req.master.id)).includes(forMasterId)) {
        return res.status(403).json({ success: false, message: 'Not authorized for this master', data: null });
      }
    }
    const allotmentOwnerId = forMasterId || (req.master ? req.master.id : null);
    if (allotmentOwnerId) {
      const Master = require('../models/Master');
      const { isGroupAllotted } = require('../services/scriptQuantityCopyService');
      const master = await Master.findById(allotmentOwnerId).select('allotted_script_quantity_groups').lean();
      lotNames = lotNames.filter(name => isGroupAllotted(master, exchange_name, name));
    }

    res.status(200).json({
      success: true,
      message: 'Lot names retrieved successfully',
      data: lotNames
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

/**
 * GET /api/admin/grouped-quantities/unique-raw-names/:segment
 * Returns all unique raw_name values from KiteInstrument for a given segment,
 * along with the lot_size from the first matching instrument.
 */
const getUniqueRawNamesBySegment = async (req, res) => {
  try {
    const { segment } = req.params;

    if (!segment) {
      return res.status(400).json({
        success: false,
        message: 'Segment is required',
        data: null
      });
    }

    const normalizedSegment = segment.toUpperCase();

    // Map segment to query filters
    let filter = { is_active: true };

    if (normalizedSegment === 'NFO-FUT') {
      filter.segment = 'NFO-FUT';
    } else if (normalizedSegment === 'NFO-OPT') {
      filter.segment = 'NFO-OPT';
    } else if (normalizedSegment === 'MCX-FUT') {
      filter.segment = 'MCX-FUT';
    } else if (normalizedSegment === 'MCX-OPT') {
      filter.segment = 'MCX-OPT';
    } else if (normalizedSegment === 'INDICES') {
      // Massive-fed index futures (S&P 500/Nasdaq 100/Dow Jones 30/Russell
      // 2000/Nikkei 225) were seeded with segment: 'GLOBAL', not 'INDICES'
      // (see seedGlobalFutures.js) — match both or they never show up here.
      filter.segment = { $in: ['INDICES', 'GLOBAL'] };
    } else if (normalizedSegment === 'NSE') {
      filter.exchange = 'NSE';
      filter.instrument_type = 'EQ';
    } else {
      // Generic fallback: try segment first, then exchange
      filter.segment = normalizedSegment;
    }

    // Aggregate unique raw_names with their lot_size
    const results = await KiteInstrument.aggregate([
      { $match: filter },
      {
        $group: {
          _id: '$raw_name',
          lot_size: { $first: '$lot_size' },
          instrument_type: { $first: '$instrument_type' },
          segment: { $first: '$segment' },
          exchange: { $first: '$exchange' }
        }
      },
      { $sort: { _id: 1 } }
    ]);

    const rawNames = results.map(r => ({
      raw_name: r._id,
      lot_size: r.lot_size || 1,
      instrument_type: r.instrument_type,
      segment: r.segment,
      exchange: r.exchange,
      category: categoryForNfoScript(r.segment, r._id)
    }));

    res.status(200).json({
      success: true,
      message: `Found ${rawNames.length} unique instruments for ${normalizedSegment}`,
      data: rawNames
    });
  } catch (error) {
    console.error('Error fetching unique raw names:', error);
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

/**
 * POST /api/admin/grouped-quantities/bulk-create
 * Creates a group with all instruments (raw_names) for a segment.
 * Body: { exchange_name, lot_name, default_max_qty, default_break_qty }
 * Auto-populates all unique raw_names from KiteInstrument for that segment.
 */
const bulkCreateGroup = async (req, res) => {
  try {
    const { exchange_name, lot_name, default_max_qty, default_break_qty } = req.body;

    if (!exchange_name || !lot_name || default_max_qty === undefined || default_break_qty === undefined) {
      return res.status(400).json({
        success: false,
        message: 'exchange_name, lot_name, default_max_qty, and default_break_qty are required',
        data: null
      });
    }

    const normalizedExchange = exchange_name.toUpperCase();

    // Build filter for KiteInstrument
    let filter = { is_active: true };
    if (normalizedExchange === 'NFO-FUT') {
      filter.segment = 'NFO-FUT';
    } else if (normalizedExchange === 'NFO-OPT') {
      filter.segment = 'NFO-OPT';
    } else if (normalizedExchange === 'MCX-FUT') {
      filter.segment = 'MCX-FUT';
    } else if (normalizedExchange === 'MCX-OPT') {
      filter.segment = 'MCX-OPT';
    } else if (normalizedExchange === 'INDICES') {
      filter.segment = { $in: ['INDICES', 'GLOBAL'] };
    } else if (normalizedExchange === 'NSE') {
      filter.exchange = 'NSE';
      filter.instrument_type = 'EQ';
    } else {
      filter.segment = normalizedExchange;
    }

    // Get unique raw_names with lot_size
    const results = await KiteInstrument.aggregate([
      { $match: filter },
      {
        $group: {
          _id: '$raw_name',
          lot_size: { $first: '$lot_size' }
        }
      },
      { $sort: { _id: 1 } }
    ]);

    if (results.length === 0) {
      return res.status(404).json({
        success: false,
        message: `No instruments found for segment ${normalizedExchange}`,
        data: null
      });
    }

    // Bulk upsert all instruments into GroupedQuantity
    const bulkOps = results.map(r => ({
      updateOne: {
        filter: {
          exchange_name: normalizedExchange,
          lot_name: lot_name,
          raw_name: r._id,
          deleted_at: null
        },
        update: {
          $setOnInsert: {
            exchange_name: normalizedExchange,
            lot_name: lot_name,
            raw_name: r._id,
            instrument_id: '',
            instrument_symbol: r._id,
            
            lot_size: r.lot_size || 1,
            // Limits only for a NEW row (owner, 9 Nov 2026): creating a group
            // under a name that already exists used to reset every row of
            // that group to these defaults.
            max_qty: default_max_qty,
            break_qty: default_break_qty,
            created_at: new Date()
          },
          $set: {
            updated_at: new Date(),
            deleted_at: null
          }
        },
        upsert: true
      }
    }));

    const bulkResult = await GroupedQuantity.bulkWrite(bulkOps);

    res.status(201).json({
      success: true,
      message: `Group "${lot_name}" created with ${results.length} instruments for ${normalizedExchange}`,
      data: {
        exchange_name: normalizedExchange,
        lot_name: lot_name,
        total_instruments: results.length,
        inserted: bulkResult.upsertedCount,
        existing: results.length - bulkResult.upsertedCount
      }
    });
  } catch (error) {
    console.error('Error bulk creating group:', error);
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

/**
 * GET /api/admin/grouped-quantities/group/:exchange_name/:lot_name
 * Returns all instruments in a specific group (exchange + lot_name).
 */
const getGroupInstruments = async (req, res) => {
  try {
    const { exchange_name, lot_name } = req.params;
    const { page = 1, limit = 500 } = req.query;

    if (!exchange_name || !lot_name) {
      return res.status(400).json({
        success: false,
        message: 'exchange_name and lot_name are required',
        data: null
      });
    }

    const filter = {
      exchange_name: exchange_name.toUpperCase(),
      lot_name: lot_name,
      deleted_at: null
    };

    const instruments = await GroupedQuantity.find(filter)
      .limit(parseInt(limit))
      .skip((parseInt(page) - 1) * parseInt(limit))
      .sort({ raw_name: 1 });

    const count = await GroupedQuantity.countDocuments(filter);

    res.status(200).json({
      success: true,
      message: 'Group instruments retrieved successfully',
      data: {
        instruments: instruments.map(i => i.toJSON()),
        total: count,
        page: parseInt(page),
        pages: Math.ceil(count / parseInt(limit))
      }
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// ============================================
// Shared helper: build KiteInstrument filter from segment name
// ============================================
function buildSegmentFilter(segment) {
  const normalized = segment.toUpperCase();
  let filter = { is_active: true };
  if (normalized === 'NFO-FUT') filter.segment = 'NFO-FUT';
  else if (normalized === 'NFO-OPT') filter.segment = 'NFO-OPT';
  else if (normalized === 'MCX-FUT') filter.segment = 'MCX-FUT';
  else if (normalized === 'MCX-OPT') filter.segment = 'MCX-OPT';
  // GLOBAL tab sends 'INDICES' (legacy naming) — but the Massive-fed index
  // futures (S&P 500/Nasdaq 100/Dow Jones 30/Russell 2000/Nikkei 225) were
  // seeded with segment: 'GLOBAL', not 'INDICES' (see seedGlobalFutures.js),
  // so both must match or those scripts silently never appear in any
  // bulk-create built from this filter.
  else if (normalized === 'INDICES') filter.segment = { $in: ['INDICES', 'GLOBAL'] };
  else if (normalized === 'NSE') { filter.exchange = 'NSE'; filter.instrument_type = 'EQ'; }
  else filter.segment = normalized;
  return filter;
}

// ============================================
// Brokerage Settings — Bulk Create & Get by Exchange
// ============================================
const BrokerageSettings = require('../models/BrokerageSettings');

/**
 * May this master touch / read the brokerage rows owned by `ownerId` (a
 * client or master id)? Same rule as PUT /brokerage-settings/bulk-update
 * (adminRoutes.js): the row's subtree root must be in the caller's own
 * subtree. With `allowUpline` (reads only) the caller's own parent chain is
 * allowed too — a master may see the rates above him (his floor). Owner,
 * 9 Nov 2026: these two endpoints had no tree check at all.
 */
async function masterMayUseRatesOf(masterId, ownerId, { allowUpline = false } = {}) {
  const { getAllSubMasterIds } = require('../services/masterHierarchyService');
  const { resolveBrokerageOwnerMasterId } = require('./adminController');
  const ownerRoot = await resolveBrokerageOwnerMasterId(ownerId);
  if (!ownerRoot) return false;
  const subtree = await getAllSubMasterIds(String(masterId));
  if (subtree.includes(ownerRoot)) return true;
  if (!allowUpline) return false;
  const Master = require('../models/Master');
  const seen = new Set();
  for (let cur = String(masterId); cur && !seen.has(cur); ) {
    seen.add(cur);
    if (cur === String(ownerId)) return true;
    const m = await Master.findById(cur).select('master_id').lean();
    cur = m?.master_id ? String(m.master_id) : null;
  }
  return false;
}

/**
 * POST /api/admin/brokerage-settings/bulk-create
 * Body: { exchange_name, type, default_brk_value }
 */
const bulkCreateBrokerage = async (req, res) => {
  try {
    const { exchange_name, type, default_brk_value, user_id } = req.body;
    if (!exchange_name || !type || default_brk_value === undefined) {
      return res.status(400).json({ success: false, message: 'exchange_name, type, and default_brk_value are required', data: null });
    }
    // No user = the PLATFORM DEFAULT rows — admin only. A master's call
    // without a user_id (the app's create-client bug, 13 times 15 Oct–7 Nov
    // 2026) must not upsert/touch the global rows.
    if (!user_id && !req.admin) {
      return res.status(400).json({ success: false, message: 'user_id is required', data: null });
    }
    if (user_id && req.master && !(await masterMayUseRatesOf(req.master.id, user_id))) {
      return res.status(403).json({ success: false, message: 'Not authorized to set brokerage for this account', data: null });
    }
    const normalizedExchange = exchange_name.toUpperCase();
    const normalizedType = type.toUpperCase();
    const filter = buildSegmentFilter(normalizedExchange);
    const results = await KiteInstrument.aggregate([
      { $match: filter },
      { $group: { _id: '$raw_name' } },
      { $sort: { _id: 1 } }
    ]);
    if (results.length === 0) {
      return res.status(404).json({ success: false, message: `No instruments found for ${normalizedExchange}`, data: null });
    }

    // Floor validation: a master's own rate set (this endpoint's normal use
    // — creating a whole script list for one user_id in one call) cannot go
    // below their parent's rate, same rule already enforced when editing a
    // single row via updateBrokerageSettings. This endpoint had no floor
    // check at all — the most direct way for a master's own rate set to end
    // up below the platform floor from the start. Admin bypasses this, same
    // as the single-create/update paths (admin can set any rate on their
    // children). Batched (not per-script) since this writes the SAME
    // default_brk_value across every script in the exchange in one call —
    // fetch the parent's + global rows for this exchange/type once, resolve
    // each script's floor in-memory, and reject the whole batch if the
    // uniform value would violate ANY script's floor (a partial apply would
    // leave some scripts non-compliant with no indication which).
    if (user_id && !req.admin) {
      const Master = require('../models/Master');
      const ownerUser = await User.findById(user_id).select('master_id').lean();
      const ownerMaster = ownerUser ? null : await Master.findById(user_id).select('master_id').lean();
      const parentId = ownerUser ? ownerUser.master_id?.toString() : ownerMaster?.master_id?.toString();

      const parentRules = parentId
        ? await BrokerageSettings.find({ user_id: parentId, exchange_name: normalizedExchange, type: normalizedType, deleted_at: null }).lean()
        : [];
      const globalRules = await BrokerageSettings.find({ user_id: null, exchange_name: normalizedExchange, type: normalizedType, deleted_at: null }).lean();
      const parentByScript = new Map(parentRules.map(r => [r.script_name, r.brk_value]));
      const globalByScript = new Map(globalRules.map(r => [r.script_name, r.brk_value]));

      const violations = [];
      for (const r of results) {
        const floor = parentByScript.get(r._id) ?? globalByScript.get(r._id);
        if (floor !== undefined && default_brk_value < floor) {
          violations.push({ script: r._id, floor });
        }
      }
      if (violations.length > 0) {
        const sample = violations.slice(0, 5).map(v => `${v.script} (floor ${v.floor})`).join(', ');
        return res.status(422).json({
          success: false,
          message: `Brokerage cannot be less than the parent limit for ${violations.length} script(s), e.g. ${sample}`,
          data: null
        });
      }
    }

    // A master's NEW rows must not sit above an account directly under him
    // (owner, 9 Nov 2026) — existing rows are left as they are by this call.
    // Master refused with the list; admin told.
    const { childrenBelowNewRate, describeChildrenBelow } = require('../services/brokerageCopyService');
    let below = [];
    if (user_id) {
      const have = new Set((await BrokerageSettings.find({ user_id, exchange_name: normalizedExchange, type: normalizedType, deleted_at: null }).select('script_name').lean()).map(r => r.script_name));
      const newRates = results.filter(r => !have.has(r._id)).map(r => ({ exchange_name: normalizedExchange, script_name: r._id, type: normalizedType, brk_value: Number(default_brk_value) }));
      below = await childrenBelowNewRate(user_id, newRates);
    }
    if (below.length && !req.admin) {
      return res.status(422).json({ success: false, message: `Brokerage cannot be more than the rate of an account under it: ${describeChildrenBelow(below)} — raise those first`, data: { children_below: below } });
    }

    const bulkOps = results.map(r => ({
      updateOne: {
        filter: { type: type.toUpperCase(), exchange_name: normalizedExchange, script_name: r._id, user_id: user_id || null, deleted_at: null },
        update: {
          $setOnInsert: { type: type.toUpperCase(), exchange_name: normalizedExchange, script_name: r._id, user_id: user_id || null, brk_value: default_brk_value, created_at: new Date() },
          $set: { updated_at: new Date(), deleted_at: null }
        },
        upsert: true
      }
    }));
    const bulkResult = await BrokerageSettings.bulkWrite(bulkOps);
    res.status(201).json({
      success: true,
      message: `Brokerage created for ${results.length} instruments` + (below.length ? ` — note: ${below.length} account(s) under it are now below this rate: ${describeChildrenBelow(below)}` : ''),
      data: { exchange_name: normalizedExchange, type, total: results.length, inserted: bulkResult.upsertedCount, existing: results.length - bulkResult.upsertedCount, children_below: below }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

/**
 * GET /api/admin/brokerage-settings/exchange/:exchange_name
 * Query: ?type=TURNOVER WISE&page=1&limit=500
 */
const getBrokerageByExchange = async (req, res) => {
  try {
    const { exchange_name } = req.params;
    const { type, user_id, page = 1, limit = 500 } = req.query;
    if (user_id && req.master && !(await masterMayUseRatesOf(req.master.id, user_id, { allowUpline: true }))) {
      return res.status(403).json({ success: false, message: 'Not authorized to view brokerage for this account', data: null });
    }
    let filter = { exchange_name: exchange_name.toUpperCase(), user_id: user_id || null, deleted_at: null };
    if (type) filter.type = type.toUpperCase();
    filter = await withoutNonTrading(BrokerageSettings, filter, 'script_name'); // utils/hideNonTrading.js
    const items = await BrokerageSettings.find(filter)
      .limit(parseInt(limit)).skip((parseInt(page) - 1) * parseInt(limit)).sort({ script_name: 1 });
    const count = await BrokerageSettings.countDocuments(filter);
    const itemsWithCategory = items.map(i => ({
      ...i.toJSON(),
      category: categoryForNfoScript(i.exchange_name, i.script_name),
    }));
    res.status(200).json({
      success: true, data: { items: itemsWithCategory, total: count, page: parseInt(page), pages: Math.ceil(count / parseInt(limit)) }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

// ============================================
// Script Quantity — Bulk Create & Get by Exchange
// ============================================
const ScriptQuantity = require('../models/ScriptQuantity');

/**
 * POST /api/admin/script-quantities/bulk-create
 * Body: { exchange_name, default_max_qty, default_brk_qty }
 */
const bulkCreateScriptQuantity = async (req, res) => {
  try {
    const { exchange_name, default_max_qty, default_brk_qty, owner_id, owner_type } = req.body;
    if (!exchange_name || default_max_qty === undefined || default_brk_qty === undefined) {
      return res.status(400).json({ success: false, message: 'exchange_name, default_max_qty, and default_brk_qty are required', data: null });
    }
    const normalizedExchange = exchange_name.toUpperCase();
    const filter = buildSegmentFilter(normalizedExchange);
    const results = await KiteInstrument.aggregate([
      { $match: filter },
      { $group: { _id: '$raw_name', lot_size: { $first: '$lot_size' } } },
      { $sort: { _id: 1 } }
    ]);
    if (results.length === 0) {
      return res.status(404).json({ success: false, message: `No instruments found for ${normalizedExchange}`, data: null });
    }

    const effectiveOwnerId = owner_id || (req.admin ? req.admin.id : req.master?.id);
    const effectiveOwnerType = owner_id ? (owner_type || 'User') : (req.admin ? 'Admin' : 'Master');

    if (req.master) {
      // Same rule as the single create/update (services/scriptQuantityGate.js):
      // self, any sub-broker below, or any client in the tree — checked for
      // EVERY script (owner, 9 Nov 2026: only the first script was checked,
      // and the value then applied to all of them).
      const { masterScriptQtyGate } = require('../services/scriptQuantityGate');
      const over = [];
      for (const r of results) {
        const gate = await masterScriptQtyGate(req.master.id, effectiveOwnerId, effectiveOwnerType, normalizedExchange, r._id);
        if (gate.error && gate.error.status === 403) return res.status(403).json({ success: false, message: gate.error.message });
        // Same as the single create: a script with no limit to check against is refused.
        if (gate.error) { over.push(`${r._id} (${gate.error.message})`); continue; }
        if (default_max_qty > gate.ceiling) over.push(`${r._id} (limit ${gate.ceiling})`);
      }
      if (over.length > 0) {
        return res.status(400).json({ success: false, message: `Refused for ${over.length} script(s) — max_qty above the limit or no limit to check against, e.g. ${over.slice(0, 5).join(', ')}` });
      }
    }

    const baseFilter = { exchange_name: normalizedExchange, owner_id: effectiveOwnerId, owner_type: effectiveOwnerType, deleted_at: null };

    const bulkOps = results.map(r => ({
      updateOne: {
        filter: { ...baseFilter, script_name: r._id },
        update: {
          $setOnInsert: {
            exchange_name: normalizedExchange,
            script_name: r._id,
            owner_id: effectiveOwnerId,
            owner_type: effectiveOwnerType,
            max_qty: default_max_qty,
            brk_qty: default_brk_qty,
            created_at: new Date(),
          },
          // Limits only for a NEW row (owner, 9 Nov 2026): a bulk create used
          // to overwrite every existing limit of the exchange (0 blocks too).
          $set: {
            lot_size: r.lot_size || 1,
            updated_at: new Date(),
            deleted_at: null
          }
        },
        upsert: true
      }
    }));
    const bulkResult = await ScriptQuantity.bulkWrite(bulkOps);

    // Rows this call really created (existing ones were left as they were).
    const createdScripts = Object.keys(bulkResult.upsertedIds || {}).map((i) => results[Number(i)]).filter(Boolean);

    // A master's new rows reach his clients only as BLOCKS (0) — same rule
    // as joining a group (owner, 9 Nov 2026); other limits come from their group.
    if (effectiveOwnerType === 'Master' && Number(default_max_qty) === 0) {
      const { cascadeMasterRowChange } = require('../services/scriptQuantityCopyService');
      for (const r of createdScripts) {
        await cascadeMasterRowChange(effectiveOwnerId, normalizedExchange, r._id, null, 0, r.lot_size || 1);
      }
    }

    // Admin's platform rows: accounts with NO row for a script get one;
    // existing limits are never overwritten (it used to reset every account
    // on the exchange, one script at a time).
    // Admin platform rows, same rule as joining (owner, 9 Nov 2026): a script
    // this call CREATED reaches accounts by cascadeAdminRowChange (fill the ones
    // with no row; a 0 default is a block for everyone under the admin). A
    // script the admin already had keeps its value: accounts with no row get
    // THAT value (a block already went out when it was set).
    if (effectiveOwnerType === 'Admin') {
      const { fillMissingScriptsGlobally, cascadeAdminRowChange } = require('../services/scriptQuantityCopyService');
      const created = new Set(createdScripts.map((r) => r._id));
      for (const r of createdScripts) {
        await cascadeAdminRowChange(effectiveOwnerId, normalizedExchange, r._id, null, Number(default_max_qty), { lot_size: r.lot_size || 1, brk_qty: default_brk_qty });
      }
      const existing = await ScriptQuantity.find({ owner_id: effectiveOwnerId, owner_type: 'Admin', exchange_name: normalizedExchange, script_name: { $in: results.filter((r) => !created.has(r._id)).map((r) => r._id) }, max_qty: { $gt: 0 }, deleted_at: null }).select('script_name lot_size max_qty brk_qty').lean();
      if (existing.length) {
        await fillMissingScriptsGlobally(normalizedExchange, existing.map((r) => ({ script_name: r.script_name, lot_size: r.lot_size || 1, max_qty: r.max_qty, brk_qty: r.brk_qty })), effectiveOwnerId);
      }
    }

    res.status(201).json({
      success: true,
      message: `Script quantity created for ${results.length} instruments`,
      data: { exchange_name: normalizedExchange, total: results.length, inserted: bulkResult.upsertedCount, existing: results.length - bulkResult.upsertedCount }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

/**
 * GET /api/admin/script-quantities/exchange/:exchange_name
 */
const getScriptQuantityByExchange = async (req, res) => {
  try {
    const { exchange_name } = req.params;
    const { page = 1, limit = 500, owner_id } = req.query;
    const upperName = exchange_name.toUpperCase();
    // Map GLOBAL → INDICES (same segment naming as brokerage/trade margin)
    const mappedName = upperName === 'GLOBAL' ? 'INDICES' : upperName;
    // Try exact match first, then base exchange (e.g. MCX-FUT → MCX)
    const baseExchange = mappedName.includes('-') ? mappedName.split('-')[0] : null;
    const exchangeFilter = baseExchange
      ? { $in: [mappedName, baseExchange] }
      : mappedName;
    let filter = { exchange_name: exchangeFilter, deleted_at: null };

    // If owner_id is provided, filter to that specific master/user's ScriptQuantity
    if (owner_id) {
      // A master could otherwise pass ANY owner_id (belonging to an unrelated
      // tenant) and read that account's script-quantity limits — this filter
      // previously trusted the query param outright. Admin is unrestricted,
      // matching every other owner-scoped endpoint in this codebase.
      if (req.master) {
        const { getAllSubMasterIds } = require('../services/masterHierarchyService');
        const allowedMasterIds = await getAllSubMasterIds(req.master.id);
        const ownerMasterId = owner_id === req.master.id
          ? req.master.id
          : await resolveScriptQuantityOwnerMasterId(owner_id);
        if (!ownerMasterId || !allowedMasterIds.includes(ownerMasterId)) {
          return res.status(403).json({ success: false, message: 'Not authorized to view script quantities for this account', data: null });
        }
      }
      filter.owner_id = owner_id;
      filter = await withoutNonTrading(ScriptQuantity, filter, 'script_name'); // utils/hideNonTrading.js
      const items = await ScriptQuantity.find(filter)
        .limit(parseInt(limit)).skip((parseInt(page) - 1) * parseInt(limit)).sort({ script_name: 1 });
      const count = await ScriptQuantity.countDocuments(filter);
      return res.status(200).json({
        success: true, data: { items: items.map(i => i.toJSON()), total: count, page: parseInt(page), pages: Math.ceil(count / parseInt(limit)) }
      });
    }

    // Admin/Master viewing global list: deduplicate by script_name, prefer Admin-owned records
    // This avoids showing one entry per master/user for the same script
    filter = await withoutNonTrading(ScriptQuantity, filter, 'script_name'); // utils/hideNonTrading.js
    const allItems = await ScriptQuantity.find(filter).sort({ owner_type: 1, script_name: 1 }).lean();

    // Deduplicate: keep one per script_name (prefer Admin > Master > User)
    const seen = new Map();
    for (const item of allItems) {
      const key = item.script_name;
      if (!seen.has(key)) {
        seen.set(key, item);
      } else {
        // Prefer Admin-owned, then Master, then User
        const existing = seen.get(key);
        const priority = { 'Admin': 0, 'Master': 1, 'User': 2 };
        // ?? (not ||): Admin's priority is 0, and "0 || 2" made every Master
        // row replace the Admin row (owner, 9 Nov 2026).
        if ((priority[item.owner_type] ?? 2) < (priority[existing.owner_type] ?? 2)) {
          seen.set(key, item);
        }
      }
    }

    const uniqueItems = Array.from(seen.values())
      .sort((a, b) => a.script_name.localeCompare(b.script_name));
    
    // Paginate
    const total = uniqueItems.length;
    const start = (parseInt(page) - 1) * parseInt(limit);
    const paginatedItems = uniqueItems.slice(start, start + parseInt(limit));

    // Transform to match toJSON format
    const items = paginatedItems.map(item => {
      const ret = { ...item };
      ret.id = ret._id;
      delete ret._id;
      delete ret.__v;
      return ret;
    });

    res.status(200).json({
      success: true, data: { items, total, page: parseInt(page), pages: Math.ceil(total / parseInt(limit)) }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

module.exports = {
  getLotNamesByExchange,
  getUniqueRawNamesBySegment,
  bulkCreateGroup,
  getGroupInstruments,
  bulkCreateBrokerage,
  getBrokerageByExchange,
  bulkCreateScriptQuantity,
  getScriptQuantityByExchange
};
