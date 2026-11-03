'use strict';

// Deterministic trade sets for the equity engine golden checks (goldenCompare.js and
// tests/cashEqEngine.unit.test.js). Same seed → same scenario, on any machine.

function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 4294967296;
  };
}

const pad = (n) => String(n).padStart(2, '0');
const SCRIPTS = ['RELIANCE', 'INFY', 'HDFCBANK', 'KPIGREEN', 'TATAMOTORS', 'SBIN'];
const BASE = { RELIANCE: 2900, INFY: 1490, HDFCBANK: 1740, KPIGREEN: 352.4, TATAMOTORS: 968.9, SBIN: 812.35 };

function datesBetween(from, to) {
  const out = [];
  const d = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  for (; d <= end; d.setUTCDate(d.getUTCDate() + 1)) {
    out.push({ date: d.toISOString().slice(0, 10), weekday: d.getUTCDay() });
  }
  return out;
}

/**
 * One scenario: accounts, slabs, trades, ledger entries, monthly settlements (Jul–Oct 2026)
 * and the as-of dates to evaluate. Covers intraday + delivery, partial sells, selling more
 * than held, BF/CF entries, higher-side-only, PCT/FIX/min rate slabs, Dr/Cr openings,
 * deposits/withdrawals/journals, missing bhav prices and same-second entries.
 */
function makeScenario(seed) {
  const r = rng(seed);
  const pick = (arr) => arr[Math.floor(r() * arr.length)];
  const money = (max) => Math.round(r() * max * 100) / 100;
  const tick = (p) => Math.round(p * 20) / 20; // NSE tick 0.05

  const nClients = 1 + Math.floor(r() * 3);
  const scripts = SCRIPTS.slice(0, 2 + Math.floor(r() * 4));
  const accounts = [];
  const slabs = [];
  let slabId = 1;
  for (let c = 0; c < nClients; c++) {
    const code = `C${pad(c + 1)}`;
    accounts.push({
      code, name: code, type: 'Customer',
      openingBalance: pick([0, 10000, 250000, 500000, 1000000, money(2000000)]),
      openingType: r() < 0.8 ? 'Cr' : 'Dr',
      mobile: '', email: '', address: '', remark: '',
      interestPct: pick([12, 15, 18, 18, 21.5]),
      maxFutLots: 0,
    });
    const mode = r() < 0.75 ? 'PCT' : 'FIX';
    slabs.push({
      id: slabId++, clientCode: code, segment: 'NSEEQ', scriptWise: false, script: '', mode,
      delPct: pick([0.1, 0.25, 0.5]), intraPct: pick([0.01, 0.03, 0.05]),
      fixDel: pick([0.5, 1, 2]), fixIntra: pick([0.1, 0.25]),
      higherSideOnly: r() < 0.4, minRate: r() < 0.2 ? pick([0.05, 0.5, 1]) : 0,
      minPct: r() < 0.2 ? 0.02 : 0, minPctOnDel: r() < 0.2 ? 0.3 : 0,
    });
    if (r() < 0.4) {
      slabs.push({
        id: slabId++, clientCode: code, segment: 'NSEEQ', scriptWise: true, script: pick(scripts), mode: 'PCT',
        delPct: 0.2, intraPct: 0.02, fixDel: 0, fixIntra: 0, higherSideOnly: r() < 0.5, minRate: 0, minPct: 0, minPctOnDel: 0,
      });
    }
  }

  const days = datesBetween('2026-07-01', '2026-10-31').filter((d) => d.weekday >= 1 && d.weekday <= 5);
  const trades = [];
  const held = new Map(); // client|script → qty (rough, to make sells realistic)
  let id = 1;
  const nTrades = 20 + Math.floor(r() * 80);
  for (let k = 0; k < nTrades; k++) {
    const { date } = pick(days);
    const acc = pick(accounts);
    const script = pick(scripts);
    const key = `${acc.code}|${script}`;
    const have = held.get(key) || 0;
    const side = have > 0 && r() < 0.45 ? 'S' : 'B';
    const qty = side === 'S' && r() < 0.8 ? Math.max(1, Math.floor(have * pick([0.25, 0.5, 1, 1.3]))) : pick([1, 10, 50, 100, 250, 1000]);
    const rate = tick(BASE[script] * (0.85 + r() * 0.3));
    const time = `${pad(9 + Math.floor(r() * 6))}:${pad(Math.floor(r() * 60))}:${pad(r() < 0.1 ? 0 : Math.floor(r() * 60))}`;
    const tradeType = r() < 0.03 ? pick(['BF', 'CF']) : 'NRM';
    trades.push({
      id: id++, ot: 'O', date, valan: '', segment: 'NSEEQ', script, option: '', strike: 0, tradeType, side,
      lot: qty, qty, rate, clientCode: acc.code, user: 'gen', ip: '', addTime: `${date} ${time}`,
    });
    held.set(key, Math.max(0, have + (side === 'B' ? qty : -qty)));
    // Same-day round trip now and then (intraday).
    if (r() < 0.2) {
      const q2 = pick([qty, Math.max(1, Math.floor(qty / 2)), qty * 2]);
      trades.push({
        id: id++, ot: 'O', date, valan: '', segment: 'NSEEQ', script, option: '', strike: 0, tradeType: 'NRM',
        side: side === 'B' ? 'S' : 'B', lot: q2, qty: q2, rate: tick(rate * (0.98 + r() * 0.04)), clientCode: acc.code,
        user: 'gen', ip: '', addTime: `${date} 15:${pad(Math.floor(r() * 30))}:00`,
      });
    }
  }

  const entries = [];
  let entryId = 1;
  for (const acc of accounts) {
    const n = Math.floor(r() * 4);
    for (let k = 0; k < n; k++) {
      entries.push({
        id: entryId++, clientCode: acc.code, date: pick(days).date,
        kind: pick(['DEPOSIT', 'DEPOSIT', 'WITHDRAWAL', 'JOURNAL_CR', 'JOURNAL_DR']),
        amount: money(300000) || 1000, narration: r() < 0.5 ? 'by bank' : '', user: 'gen',
      });
    }
  }

  // Month-ends: bhav on the month's last weekday, keyed on the 1st of the next month.
  const settlements = [];
  const months = [['2026-07', '2026-08-01'], ['2026-08', '2026-09-01'], ['2026-09', '2026-10-01'], ['2026-10', '2026-11-01']];
  let sid = 1;
  for (const [ym, settleDate] of months) {
    if (r() < 0.15) continue; // a month not settled yet
    const lastDay = days.filter((d) => d.date.startsWith(ym)).pop().date;
    const prices = {};
    for (const s of scripts) if (r() > 0.05) prices[s] = tick(BASE[s] * (0.85 + r() * 0.3));
    settlements.push({ id: sid++, segment: 'NSEEQ', settleDate, priceDate: lastDay, prices, sources: {} });
  }

  const asOfs = ['2026-07-31', '2026-08-15', '2026-08-31', '2026-09-01', '2026-09-30', '2026-10-01', '2026-10-20', '2026-10-31', '2026-11-01', '2026-11-03'];
  const live = {};
  for (const s of scripts) if (r() < 0.7) live[`NSEEQ|${s}`] = tick(BASE[s] * (0.85 + r() * 0.3));

  return { seed, accounts, slabs, trades, entries, settlements, asOfs, live };
}

/** Stable JSON of engine outputs: Maps → sorted [key, value] arrays, Sets → sorted arrays. */
function canonical(value) {
  return JSON.stringify(value, (_k, v) => {
    if (v instanceof Map) return [...v.entries()].sort((a, b) => (String(a[0]) < String(b[0]) ? -1 : String(a[0]) > String(b[0]) ? 1 : 0));
    if (v instanceof Set) return [...v].sort();
    if (typeof v === 'number' && Object.is(v, -0)) return 0;
    return v;
  });
}

/**
 * Runs every equity function of `engine` (original or port) over a scenario and returns
 * one plain object of all results. `ledgerFn` / `carryFn` / `lotsFn` come from ledger.ts
 * in the original and from engine.js in the port.
 */
function runScenario(sc, fns) {
  const out = {};
  const calcs = fns.computeTradeCalcs(sc.trades, sc.slabs, []);
  out.calcs = calcs;
  out.positions = fns.computePositions(sc.trades, calcs, sc.live);
  out.lots = sc.accounts.map((a) => fns.buildEquityLots(sc.trades.filter((t) => t.clientCode === a.code), calcs));
  out.ledgers = [];
  out.carry = [];
  for (const asOf of sc.asOfs) {
    for (const a of sc.accounts) {
      const l = fns.computeClientLedger(a, sc.trades, calcs, sc.entries, sc.settlements, asOf);
      delete l.ncdexPostings; // original only (NCDEX)
      out.ledgers.push(l);
    }
    const c = fns.carryToSettlement(sc.trades, calcs, sc.settlements, asOf);
    out.carry.push({ trades: c.trades, calcs: c.calcs, since: c.since, positions: fns.computePositions(c.trades, c.calcs, sc.live) });
  }
  return out;
}

module.exports = { makeScenario, runScenario, canonical };
