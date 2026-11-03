'use strict';

// Equity master sharing for one confirmed month — pure functions over the month-end
// snapshot. Same models as the F&O weekly sharing (weeklyAdminController):
//   • P&L: ceiling model — each level keeps (its share − the share it gave the child on
//     that line) of the client's gross P&L (house view: a client loss is +); admin = 100.
//   • Brokerage and interest: rate-gap model — a level keeps the markup between what the
//     client was charged and the level's OWN rate (its "clearance"), plus its share of its
//     own clearance; the rest of its clearance goes up. Every level's cut adds up to the
//     client's total exactly (tested).
// Equity numbers only — nothing here reads or writes F&O sharing.

const r2 = (n) => Math.round(n * 100) / 100;

/** Share % of a level for one pool ('pnl_share' | 'brokerage_share' | 'interest_share'). */
function ceiling(callerRole, callerId, masters, field) {
  if (callerRole === 'admin') return 100;
  return masters.get(String(callerId))?.[field] || 0;
}

/**
 * Sharing statement for the caller (admin, or an equity master) from a confirmed run:
 *   clients: [{ client_id, username, name, chain: [direct master … top], gross_pnl,
 *              brokerage, interest, clearances: { masterId: { brokerage, interest } } }]
 *   masters: [{ _id, parent_id, username, name, pnl_share, brokerage_share, interest_share }]
 * Rows: the caller's direct clients and direct sub-masters (whole sub-tree in one row).
 */
function statement({ role, id }, run) {
  const masters = new Map((run.masters || []).map((m) => [String(m._id), m]));
  const caller = role === 'admin' ? null : String(id);
  const ceil = (field) => ceiling(role, caller, masters, field);
  const cP = ceil('pnl_share');
  const cB = ceil('brokerage_share');
  const cI = ceil('interest_share');
  const clr = (c, mid, k) => (mid ? (c.clearances?.[mid]?.[k] || 0) : 0);

  const clientRows = [];
  const groups = new Map(); // direct child master id -> clients
  for (const c of run.clients || []) {
    const chain = (c.chain || []).map(String);
    if (caller === null) {
      const top = chain[chain.length - 1];
      if (!top) continue;
      if (!groups.has(top)) groups.set(top, []);
      groups.get(top).push(c);
      continue;
    }
    const at = chain.indexOf(caller);
    if (at < 0) continue; // not in the caller's tree
    if (at === 0) clientRows.push(c);
    else {
      const child = chain[at - 1];
      if (!groups.has(child)) groups.set(child, []);
      groups.get(child).push(c);
    }
  }

  const rows = [];
  for (const c of clientRows) {
    const house = -c.gross_pnl;
    const cb = clr(c, caller, 'brokerage');
    const ci = clr(c, caller, 'interest');
    rows.push({
      type: 'client', id: c.client_id, username: c.username, name: c.name,
      gross_pnl: r2(c.gross_pnl), total_pnl: r2(house), brokerage: r2(c.brokerage), interest: r2(c.interest),
      own_brokerage: r2(cb), own_interest: r2(ci),
      caller_pnl: r2(house * cP / 100),
      caller_brk: r2(c.brokerage - cb + cb * cB / 100),
      caller_int: r2(c.interest - ci + ci * cI / 100),
      owed_up_pnl: r2(house * (100 - cP) / 100),
      owed_up_brk: r2(cb * (100 - cB) / 100),
      owed_up_int: r2(ci * (100 - cI) / 100),
    });
  }
  for (const [mid, list] of groups) {
    const m = masters.get(mid) || {};
    const sum = (f) => list.reduce((a, c) => a + f(c), 0);
    const gross = sum((c) => c.gross_pnl);
    const house = -gross;
    const mB = sum((c) => clr(c, mid, 'brokerage'));
    const mI = sum((c) => clr(c, mid, 'interest'));
    const cbS = sum((c) => clr(c, caller, 'brokerage'));
    const ciS = sum((c) => clr(c, caller, 'interest'));
    rows.push({
      type: 'master', id: mid, username: m.username, name: m.name, clients: list.length,
      gross_pnl: r2(gross), total_pnl: r2(house), brokerage: r2(sum((c) => c.brokerage)), interest: r2(sum((c) => c.interest)),
      own_brokerage: r2(mB), own_interest: r2(mI),
      caller_pnl: r2(house * (cP - (m.pnl_share || 0)) / 100),
      caller_brk: r2(mB * (100 - (m.brokerage_share || 0)) / 100 - cbS * (100 - cB) / 100),
      caller_int: r2(mI * (100 - (m.interest_share || 0)) / 100 - ciS * (100 - cI) / 100),
      owed_up_pnl: r2(house * (100 - cP) / 100),
      owed_up_brk: r2(cbS * (100 - cB) / 100),
      owed_up_int: r2(ciS * (100 - cI) / 100),
    });
  }
  rows.sort((a, b) => (a.type === b.type ? String(a.username).localeCompare(String(b.username)) : a.type === 'master' ? -1 : 1));
  const tot = (k) => r2(rows.reduce((a, r) => a + r[k], 0));
  const totals = {};
  for (const k of ['gross_pnl', 'total_pnl', 'brokerage', 'interest', 'caller_pnl', 'caller_brk', 'caller_int', 'owed_up_pnl', 'owed_up_brk', 'owed_up_int']) totals[k] = tot(k);
  totals.caller_total = r2(totals.caller_pnl + totals.caller_brk + totals.caller_int);
  totals.owed_up_total = r2(totals.owed_up_pnl + totals.owed_up_brk + totals.owed_up_int);
  return { month: run.month, shares: { pnl: cP, brokerage: cB, interest: cI }, rows, totals };
}

module.exports = { statement, ceiling };
