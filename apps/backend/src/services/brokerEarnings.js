'use strict';

/**
 * Broker earnings — what each introducing broker is owed from their clients'
 * brokerage. Read-only arithmetic over completed trades; nothing here writes
 * anywhere or feeds the ledger / weekly report / settlement.
 *
 * Per fill: TURNOVER WISE -> executed_price × qty × value / 10000 (the same
 * formula brokerageService uses for brk_value); LOT WISE -> qty / lot_size ×
 * value. Never more than the brokerage the client actually paid on the fill
 * (trade.brokerage), and 0 on a brokerage-exempt fill.
 */

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

function normSegment(segment) {
  const s = String(segment || '').trim().toUpperCase();
  return s === 'GLOBAL' ? 'INDICES' : s;
}

/** Monday 00:00 IST of the week containing `date`, as a Date. */
function weekStartIST(date) {
  const ist = new Date(new Date(date).getTime() + IST_OFFSET_MS);
  const daysSinceMonday = (ist.getUTCDay() + 6) % 7;
  return new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate() - daysSinceMonday) - IST_OFFSET_MS);
}

/** The broker's share of one fill: { turnover, lots, amount, capped }. */
function brokerShare({ type, value, price, quantity, lotSize, brokerage, exempt }) {
  const qty = Number(quantity) || 0;
  const turnover = (Number(price) || 0) * qty;
  const lots = lotSize > 0 ? qty / lotSize : 0;
  if (exempt || !(value > 0) || qty <= 0) return { turnover, lots, amount: 0, capped: false };
  const raw = type === 'LOT WISE' ? lots * value : turnover * (value / 10000);
  const paid = Number(brokerage);
  if (Number.isFinite(paid) && paid >= 0 && raw > paid) return { turnover, lots, amount: paid, capped: true };
  return { turnover, lots, amount: raw, capped: false };
}

/**
 * Rows of { broker_id, link_id, user_id, segment, type, value, week_start,
 * fills, turnover, lots, amount, capped_fills } for every fill inside both its
 * client's link period [link.from, link.to) and the asked range [from, to).
 *
 * links:       [{ _id, broker_id, user_id, rates: [{ segment, type, value }], from, to }]
 * trades:      completed fills of the linked clients
 * instruments: Map instrument_token -> { segment, lot_size }
 */
function computeBrokerEarnings({ links, trades, instruments, from, to }) {
  const linksByUser = new Map();
  for (const link of links) {
    const key = String(link.user_id);
    if (!linksByUser.has(key)) linksByUser.set(key, []);
    linksByUser.get(key).push(link);
  }
  const fromMs = from ? new Date(from).getTime() : -Infinity;
  const toMs = to ? new Date(to).getTime() : Infinity;
  const rows = new Map();

  for (const trade of trades) {
    const at = new Date(trade.executed_at || trade.createdAt).getTime();
    if (!(at >= fromMs && at < toMs)) continue;
    const link = (linksByUser.get(String(trade.user_id)) || []).find((l) =>
      at >= new Date(l.from).getTime() && (l.to == null || at < new Date(l.to).getTime()));
    if (!link) continue;
    const inst = instruments.get(String(trade.instrument_token)) || instruments.get(Number(trade.instrument_token)) || {};
    const segment = normSegment(inst.segment || trade.segment || trade.exchange);
    const rate = (link.rates || []).find((r) => normSegment(r.segment) === segment);
    if (!rate || !(rate.value > 0)) continue;

    const share = brokerShare({
      type: rate.type,
      value: rate.value,
      price: trade.executed_price,
      quantity: trade.executed_quantity ?? trade.quantity,
      lotSize: inst.lot_size || trade.lot_size || 0,
      brokerage: trade.brokerage,
      exempt: trade.brokerage_exempt === true,
    });
    const week = weekStartIST(at);
    const key = `${link._id}|${segment}|${week.getTime()}`;
    let row = rows.get(key);
    if (!row) {
      row = { broker_id: String(link.broker_id), link_id: String(link._id), user_id: String(link.user_id), segment,
        type: rate.type, value: rate.value, week_start: week, fills: 0, turnover: 0, lots: 0, amount: 0, capped_fills: 0 };
      rows.set(key, row);
    }
    row.fills++;
    row.turnover += share.turnover;
    row.lots += share.lots;
    row.amount += share.amount;
    if (share.capped) row.capped_fills++;
  }

  return [...rows.values()]
    .map((r) => ({ ...r, turnover: round2(r.turnover), lots: round2(r.lots), amount: round2(r.amount) }))
    .sort((a, b) => a.week_start - b.week_start || a.broker_id.localeCompare(b.broker_id) || a.user_id.localeCompare(b.user_id) || a.segment.localeCompare(b.segment));
}

function round2(x) {
  return Math.round((Number(x) || 0) * 100) / 100;
}

module.exports = { computeBrokerEarnings, brokerShare, weekStartIST, normSegment };
