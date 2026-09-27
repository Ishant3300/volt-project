const BrokerageSettings = require('../models/BrokerageSettings');
const KiteInstrument = require('../models/KiteInstrument');
const ScriptQuantity = require('../models/ScriptQuantity');

/**
 * Canonical brokerage calculation — shared by marginSquareOffService.js,
 * masterUserController.js, priceQueueService.js, and orderExecutionService.js.
 *
 * Rule matching previously matched only on `trade.exchange` (the coarse
 * exchange, e.g. "NFO") instead of the instrument's real segment (e.g.
 * "NFO-FUT"), and required an exact non-empty script_name with no fallback
 * to a segment/exchange-wide wildcard rule (script_name empty) — the same
 * pattern already fixed in tradeReportController.js and
 * weeklyAdminController.js. Any admin who configured a segment-level
 * default rule instead of one rule per individual script got ₹0 brokerage
 * silently charged from every consumer of this function. Now uses the same
 * 4-level fallback (script+segment, script-only, segment+wildcard,
 * bare-exchange+wildcard) as the already-correct tradeController.js
 * immediate-fill path.
 */
/**
 * @param {object} trade
 * @param {object} [session]
 * @param {{instrument?: object, rules?: object[]}} [preloaded] - bulk callers
 *   (rollover) pass the instrument and the owner's rule set loaded once —
 *   `rules` must be exactly what the lookups below would return (the user's
 *   own rows, or the global rows when the user has none). Same matching.
 */
async function calculateBrokerage(trade, session, preloaded = null) {
  try {
    const instrument = preloaded?.instrument !== undefined
      ? preloaded.instrument
      : await KiteInstrument.findOne({ instrument_token: trade.instrument_token }).session(session).lean();
    const rawName = instrument?.raw_name || instrument?.name
      || (trade.tradingsymbol || '').replace(/[0-9]+[A-Z]+$/, '').trim() || null;
    const seg = instrument?.segment || trade.exchange || '';
    const userId = trade.user_id || null;

    const rules = preloaded?.rules || await loadBrokerageRules(userId, session);

    let rule = null;
    if (rawName && seg) rule = rules.find(r => r.script_name?.toUpperCase() === rawName.toUpperCase() && r.exchange_name === seg.toUpperCase());
    if (!rule && rawName) rule = rules.find(r => r.script_name?.toUpperCase() === rawName.toUpperCase());
    if (!rule && seg) rule = rules.find(r => r.exchange_name === seg.toUpperCase() && (!r.script_name || r.script_name.trim() === ''));
    if (!rule) rule = rules.find(r => r.exchange_name === (seg.split('-')[0] || '').toUpperCase() && (!r.script_name || r.script_name.trim() === ''));

    if (!rule) return 0;

    if (rule.type === 'TURNOVER WISE') {
        return (trade.price * trade.quantity) * (rule.brk_value / 10000);
    }
    if (rule.type !== 'LOT WISE') return 0;

    let lotSize = Number(instrument?.lot_size || 0);
    if (lotSize <= 0) {
      const lot = await ScriptQuantity.findOne({
        exchange_name: trade.exchange,
        script_name: trade.tradingsymbol,
        deleted_at: null,
      }).session(session).lean();
      lotSize = lot?.lot_size || 1;
    }

    const lots = lotSize > 0 ? trade.quantity / lotSize : trade.quantity;
    return lots * rule.brk_value;
  } catch (err) {
    console.error('Error calculating brokerage:', err);
    return 0;
  }
}

/** The rule set calculateBrokerage matches against: the user's own rows, else the global rows. */
async function loadBrokerageRules(userId, session) {
  const userRules = userId
    ? await BrokerageSettings.find({ user_id: userId, deleted_at: null }).session(session).lean()
    : [];
  if (userRules.length > 0) return userRules;
  return BrokerageSettings.find({ user_id: null, deleted_at: null }).session(session).lean();
}

module.exports = { calculateBrokerage, loadBrokerageRules };
