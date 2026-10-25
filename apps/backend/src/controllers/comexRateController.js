'use strict';

/**
 * COMEX USD→INR rate (utils/comexFx.js): admin sets base + spread; the weekly
 * settlement converts each client's COMEX net at base + spread (debit) or
 * base − spread (credit). Read: admin and masters (bills show the estimate).
 * Write: admin only, refused while a settlement is in progress so a run never
 * sees a rate change halfway.
 */

const ComexRate = require('../models/ComexRate');
const SettlementRun = require('../models/SettlementRun');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

const IN_PROGRESS = ['running', 'committed', 'finalizing'];

function view(doc) {
  if (!doc) return { base: null, spread: null, debit_rate: null, credit_rate: null, updated_by: null, updated_at: null, history: [] };
  return {
    base: doc.base,
    spread: doc.spread,
    debit_rate: doc.base + doc.spread,
    credit_rate: doc.base - doc.spread,
    updated_by: doc.updated_by,
    updated_at: doc.updated_at,
    history: (doc.history || []).slice(-20).reverse(),
  };
}

const getComexRate = async (req, res) => {
  try {
    const doc = await ComexRate.findOne({ key: 'comex' }).lean();
    res.status(200).json({ success: true, data: view(doc) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

const setComexRate = async (req, res) => {
  try {
    const base = Number(req.body?.base);
    const spread = Number(req.body?.spread);
    if (!Number.isFinite(base) || base <= 0 || base > 1000) {
      return res.status(400).json({ success: false, message: 'Base rate must be a number above 0 (e.g. 88.00)' });
    }
    if (!Number.isFinite(spread) || spread < 0 || spread >= base) {
      return res.status(400).json({ success: false, message: 'Spread must be 0 or more and less than the base rate' });
    }
    const running = await SettlementRun.findOne({ status: { $in: IN_PROGRESS } }).select('_id period_key').lean();
    if (running) {
      return res.status(409).json({ success: false, message: 'A settlement is in progress — change the COMEX rate after it finishes' });
    }
    const by = req.admin?.username || req.admin?.name || (req.admin?.id ? String(req.admin.id) : null);
    const now = new Date();
    const r2 = (n) => Math.round(n * 10000) / 10000;
    const doc = await ComexRate.findOneAndUpdate(
      { key: 'comex' },
      {
        $set: { base: r2(base), spread: r2(spread), updated_by: by, updated_at: now },
        $push: { history: { $each: [{ base: r2(base), spread: r2(spread), by, at: now }], $slice: -200 } },
      },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    ).lean();
    res.status(200).json({ success: true, data: view(doc) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

module.exports = { getComexRate, setComexRate };
