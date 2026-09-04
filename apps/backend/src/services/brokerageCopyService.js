'use strict';

/**
 * Brokerage Copy & Validation Service
 *
 * Handles:
 * 1. Copying parent's brokerage rates to a newly created child (Master/User)
 * 2. Floor validation: ensures child rate >= parent rate
 * 3. Resolving parent's rate for a given user/master + exchange + script
 */

const BrokerageSettings = require('../models/BrokerageSettings');
const User = require('../models/User');
const Master = require('../models/Master');
const KiteInstrument = require('../models/KiteInstrument');
const { categoryForNfoScript } = require('../constants/nfoIndexUnderlyings');

/**
 * Copy brokerage settings from a parent (Master) to a newly created child (Master or User).
 * Creates new BrokerageSettings records with user_id = childId, copying all rates from parentId.
 *
 * @param {string} parentId - The parent master's _id
 * @param {string} childId - The new child's _id (master or user)
 * @param {object} [session] - Optional mongoose session for transactional use
 */
async function copyBrokerageFromParent(parentId, childId, session) {
  try {
    // Get all brokerage rules for the parent
    const query = BrokerageSettings.find({ user_id: parentId, deleted_at: null });
    if (session) query.session(session);
    const parentRules = await query.lean();

    if (parentRules.length === 0) {
      // Parent has no specific rules — copy from global instead
      return copyBrokerageFromGlobal(childId, session);
    }

    const now = new Date();
    const docs = parentRules.map(rule => ({
      updateOne: {
        filter: {
          user_id: childId,
          exchange_name: rule.exchange_name,
          script_name: rule.script_name,
          type: rule.type,
          deleted_at: null,
        },
        update: {
          $setOnInsert: {
            user_id: childId,
            exchange_name: rule.exchange_name,
            script_name: rule.script_name,
            type: rule.type,
            brk_value: rule.brk_value,
            effective_from: now,
            created_at: now,
          },
          $set: { updated_at: now, deleted_at: null },
        },
        upsert: true,
      },
    }));

    if (docs.length > 0) {
      if (session) {
        await BrokerageSettings.bulkWrite(docs, { session });
      } else {
        await BrokerageSettings.bulkWrite(docs);
      }
      console.log(`📋 [BrokerageCopy] Copied ${docs.length} brokerage rules from parent ${parentId} to child ${childId}`);
    }
  } catch (e) {
    console.error(`❌ [BrokerageCopy] Error copying from parent ${parentId} to child ${childId}:`, e.message);
  }
}

/**
 * Copy global brokerage settings (user_id: null) to a newly created master.
 * Used when Admin creates a top-level master (no parent master).
 *
 * @param {string} childId - The new master's _id
 * @param {object} [session] - Optional mongoose session
 */
async function copyBrokerageFromGlobal(childId, session) {
  try {
    const query = BrokerageSettings.find({ user_id: null, deleted_at: null });
    if (session) query.session(session);
    const globalRules = await query.lean();

    if (globalRules.length === 0) return;

    const now = new Date();
    const docs = globalRules.map(rule => ({
      updateOne: {
        filter: {
          user_id: childId,
          exchange_name: rule.exchange_name,
          script_name: rule.script_name,
          type: rule.type,
          deleted_at: null,
        },
        update: {
          $setOnInsert: {
            user_id: childId,
            exchange_name: rule.exchange_name,
            script_name: rule.script_name,
            type: rule.type,
            brk_value: rule.brk_value,
            effective_from: now,
            created_at: now,
          },
          $set: { updated_at: now, deleted_at: null },
        },
        upsert: true,
      },
    }));

    if (docs.length > 0) {
      if (session) {
        await BrokerageSettings.bulkWrite(docs, { session });
      } else {
        await BrokerageSettings.bulkWrite(docs);
      }
      console.log(`📋 [BrokerageCopy] Copied ${docs.length} global brokerage rules to master ${childId}`);
    }
  } catch (e) {
    console.error(`❌ [BrokerageCopy] Error copying global rules to ${childId}:`, e.message);
  }
}

/**
 * Get the immediate parent's brokerage rate for a given target + exchange + script.
 * Walks up: User → their Master → parent Master → global (admin level)
 *
 * @param {string} targetId - The user or master whose parent rate we need
 * @param {string} targetType - 'User' or 'Master'
 * @param {string} exchangeName - e.g. 'NFO-FUT'
 * @param {string} scriptName - e.g. 'NIFTY'
 * @param {string} type - 'TURNOVER WISE' or 'LOT WISE'
 * @returns {number|null} The parent's brk_value, or null if not found
 */
async function getParentBrokerageRate(targetId, targetType, exchangeName, scriptName, type) {
  try {
    let parentId = null;

    if (targetType === 'User') {
      const user = await User.findById(targetId).select('master_id').lean();
      parentId = user?.master_id?.toString() || null;
    } else if (targetType === 'Master') {
      const master = await Master.findById(targetId).select('master_id').lean();
      parentId = master?.master_id?.toString() || null;
    }

    // Look up parent's specific rate
    if (parentId) {
      const parentRule = await BrokerageSettings.findOne({
        user_id: parentId,
        exchange_name: exchangeName.toUpperCase(),
        script_name: scriptName,
        type: type,
        deleted_at: null,
      }).lean();

      if (parentRule) return parentRule.brk_value;
    }

    // Fallback: global (admin-level) rate
    const globalRule = await BrokerageSettings.findOne({
      user_id: null,
      exchange_name: exchangeName.toUpperCase(),
      script_name: scriptName,
      type: type,
      deleted_at: null,
    }).lean();

    return globalRule?.brk_value ?? null;
  } catch (e) {
    console.error(`❌ [BrokerageCopy] Error getting parent rate:`, e.message);
    return null;
  }
}

/**
 * Validate that a new brokerage value is >= the parent's rate.
 * Returns an error message if violated, or null if valid.
 *
 * @param {string} targetId - The user/master being updated
 * @param {string} targetType - 'User' or 'Master'
 * @param {string} exchangeName
 * @param {string} scriptName
 * @param {string} type - 'TURNOVER WISE' or 'LOT WISE'
 * @param {number} newValue - The proposed brk_value
 * @returns {string|null} Error message or null if valid
 */
async function validateBrokerageFloor(targetId, targetType, exchangeName, scriptName, type, newValue) {
  const parentRate = await getParentBrokerageRate(targetId, targetType, exchangeName, scriptName, type);

  if (parentRate === null) return null; // No parent rate found — allow any value

  if (newValue < parentRate) {
    return `Brokerage cannot be less than the parent limit (${parentRate})`;
  }

  return null;
}

/**
 * Apply creation-form brokerage overrides for a newly created account —
 * real `BrokerageSettings` rows, not the display-only `MasterBaseRate`
 * table. Call this AFTER copyBrokerageFromParent/copyBrokerageFromGlobal
 * so overrides land on top of the copied baseline.
 *
 * Each entry in `overrides` is one of:
 *   - `{ exchange_name, type, brk_value, script_name }` — one specific script.
 *   - `{ exchange_name, type, brk_value, category: 'INDEX'|'STOCK' }` — every
 *     NFO-FUT/NFO-OPT script in that category (resolved against
 *     `constants/nfoIndexUnderlyings.js`, the same classification the
 *     brokerage-settings screens use).
 *   - `{ exchange_name, type, brk_value }` (neither) — every script in the
 *     segment, i.e. today's existing flat-per-segment behavior.
 *
 * @param {string} childId - the new Master/User's _id
 * @param {Array} overrides
 * @param {object} [session]
 */
async function applyBrokerageOverrides(childId, overrides, session) {
  if (!Array.isArray(overrides) || overrides.length === 0) return;

  const now = new Date();
  const ops = [];

  for (const entry of overrides) {
    if (!entry?.exchange_name || !entry?.type || entry?.brk_value === undefined || entry?.brk_value === null) continue;
    const exchangeName = String(entry.exchange_name).toUpperCase();
    const type = String(entry.type).toUpperCase();
    const brkValue = Number(entry.brk_value);

    let scriptNames;
    if (entry.script_name) {
      scriptNames = [entry.script_name];
    } else if (entry.category) {
      const category = String(entry.category).toUpperCase();
      const instrumentsQuery = KiteInstrument.find({ segment: exchangeName, is_active: true }).select('raw_name');
      if (session) instrumentsQuery.session(session);
      const instruments = await instrumentsQuery.lean();
      scriptNames = [...new Set(
        instruments
          .filter(i => categoryForNfoScript(exchangeName, i.raw_name) === category)
          .map(i => i.raw_name)
      )];
    } else {
      const instrumentsQuery = KiteInstrument.find({ segment: exchangeName, is_active: true }).select('raw_name');
      if (session) instrumentsQuery.session(session);
      const instruments = await instrumentsQuery.lean();
      scriptNames = [...new Set(instruments.map(i => i.raw_name))];
    }

    for (const scriptName of scriptNames) {
      ops.push({
        updateOne: {
          filter: { user_id: childId, exchange_name: exchangeName, script_name: scriptName, type, deleted_at: null },
          update: {
            $set: { brk_value: brkValue, updated_at: now, deleted_at: null },
            $setOnInsert: { user_id: childId, exchange_name: exchangeName, script_name: scriptName, type, effective_from: now, created_at: now },
          },
          upsert: true,
        },
      });
    }
  }

  if (ops.length > 0) {
    if (session) await BrokerageSettings.bulkWrite(ops, { session });
    else await BrokerageSettings.bulkWrite(ops);
    console.log(`📋 [BrokerageCopy] Applied ${ops.length} brokerage override(s) for ${childId}`);
  }
}

module.exports = {
  copyBrokerageFromParent,
  copyBrokerageFromGlobal,
  getParentBrokerageRate,
  validateBrokerageFloor,
  applyBrokerageOverrides,
};
