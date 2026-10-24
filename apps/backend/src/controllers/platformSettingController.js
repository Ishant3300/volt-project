'use strict';

const PlatformSetting = require('../models/PlatformSetting');
const { MIN_SETTING_KEY, MAX_PROFIT_BOOK_MINUTES, getMinProfitBookMinutes, clearMinCache } = require('../utils/profitBookTime');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

/** GET /api/admin/settings/profit-book-minimum — admin or master (create forms prefill and check it). */
const getProfitBookMinimum = async (req, res) => {
  try {
    res.json({ success: true, data: { minutes: await getMinProfitBookMinutes() } });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
};

/**
 * PUT /api/admin/settings/profit-book-minimum { minutes } — admin only.
 * Existing clients are NOT changed: one below a raised minimum keeps their
 * time until it is next changed (utils/profitBookTime.js).
 */
const setProfitBookMinimum = async (req, res) => {
  try {
    const n = Number(req.body?.minutes);
    if (!Number.isInteger(n) || n < 0 || n > MAX_PROFIT_BOOK_MINUTES) {
      return res.status(400).json({ success: false, message: `Minimum profit book time must be a whole number between 0 and ${MAX_PROFIT_BOOK_MINUTES} minutes`, data: null });
    }
    await PlatformSetting.updateOne(
      { key: MIN_SETTING_KEY },
      { $set: { value: n, updated_by: { type: 'Admin', id: req.admin.id } } },
      { upsert: true },
    );
    clearMinCache();
    res.json({ success: true, message: `Minimum profit book time set to ${n} minutes`, data: { minutes: n } });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
};

module.exports = { getProfitBookMinimum, setProfitBookMinimum };
