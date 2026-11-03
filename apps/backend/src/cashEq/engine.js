'use strict';

// NSE cash equity ("Equity" segment) — calculation engine.
//
// Port of the NSEEQ parts of Trade Terminal (D:\TradeTerminal\lib\terminal\engine.ts and
// ledger.ts). Same data shapes and the same arithmetic in the same order, so every net
// rate, lot, P&L, MTM and interest figure matches the original to the paisa — checked by
// scripts/cashEq/goldenCompare.js (original vs port on generated trade sets) and
// tests/cashEqEngine.unit.test.js. NCDEX and the F&O segments are left out.
//
// Pure functions only: no database, no prices feed, no F&O code. Nothing in the F&O
// system imports this file.
//
// Shapes (as in Trade Terminal types.ts):
//   Trade      { id, date 'YYYY-MM-DD', addTime 'YYYY-MM-DD HH:MM:SS', segment 'NSEEQ', script,
//                option '', strike 0, tradeType 'NRM'|'CF'|'BF', side 'B'|'S', qty, rate,
//                clientCode, fullPayment? }
//   Slab       { clientCode, segment, scriptWise, script, mode 'PCT'|'FIX', delPct, intraPct,
//                fixDel, fixIntra, higherSideOnly, minRate, minPct, minPctOnDel }
//   Account    { code, openingBalance, openingType 'Cr'|'Dr', interestPct }
//   Entry      { clientCode, date, kind 'DEPOSIT'|'WITHDRAWAL'|'JOURNAL_DR'|'JOURNAL_CR', amount, narration }
//   Settlement { segment 'NSEEQ', settleDate (1st of next month), priceDate (bhav date), prices { script: close } }

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

const pad = (n) => String(n).padStart(2, '0');

/** Calendar date arithmetic on 'YYYY-MM-DD' (no time zone involved). */
function addDays(dateStr, days) {
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return `${dt.getUTCFullYear()}-${pad(dt.getUTCMonth() + 1)}-${pad(dt.getUTCDate())}`;
}

/** Calendar days from `from` to `to`, counting both days (24-Aug → 24-Aug = 1). */
function daysInclusive(from, to) {
  const [y1, m1, d1] = from.split('-').map(Number);
  const [y2, m2, d2] = to.split('-').map(Number);
  return Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y1, m1 - 1, d1)) / 86_400_000) + 1;
}

// ---------------------------------------------------------------------------
// Instruments (equity: lot size 1, symbol = script unless listed otherwise)
// ---------------------------------------------------------------------------

const instrumentIndex = new WeakMap();

function findListed(instruments, segment, name) {
  let index = instrumentIndex.get(instruments);
  if (!index) {
    index = new Map(instruments.map((i) => [`${i.segment}|${i.name}`, i]));
    instrumentIndex.set(instruments, index);
  }
  return index.get(`${segment}|${name.trim().toUpperCase()}`);
}

function instrumentKey(t) {
  return `${t.segment}|${t.script}|${t.option}|${t.option ? t.strike : ''}`;
}

function quoteKey(t) {
  return t.option ? `${t.segment}|${t.script}|${t.strike}|${t.option}` : `${t.segment}|${t.script}`;
}

function contractLabel(t) {
  return t.option ? `${t.script} ${t.strike} ${t.option}` : t.script;
}

// ---------------------------------------------------------------------------
// Brokerage and net rate
// ---------------------------------------------------------------------------

/** Script-wise slab (matched on symbol) wins over the segment-wise slab. */
function findSlab(slabs, clientCode, segment, symbol) {
  return (
    slabs.find((s) => s.clientCode === clientCode && s.segment === segment && s.scriptWise && s.script === symbol) ??
    slabs.find((s) => s.clientCode === clientCode && s.segment === segment && !s.scriptWise) ??
    null
  );
}

/** Brokerage for one portion (intraday or delivery) of an execution. */
function portionBrokerage(slab, portion, rate, qty, lotSize) {
  if (qty <= 0) return 0;
  if (slab.mode === 'FIX') {
    const amount = portion === 'intra' ? slab.fixIntra : slab.fixDel;
    return amount * (qty / Math.max(1, lotSize));
  }
  // Minimum % / Min % On Del act as floors on the configured percentage.
  const pct = portion === 'intra' ? Math.max(slab.intraPct, slab.minPct) : Math.max(slab.delPct, slab.minPctOnDel);
  let perUnit = rate * (pct / 100);
  if (slab.minRate > 0 && perUnit < slab.minRate) perUnit = slab.minRate;
  return perUnit * qty;
}

/**
 * Brokerage and net rate for every trade.
 *
 * Trades are grouped by date + client + script. Within a group the matched quantity
 * min(ΣBuy, ΣSell) is intraday, allocated FIFO by entry time on each side; the rest is
 * delivery. With "higher side only" the intraday portion is charged only on the side
 * with the larger intraday turnover (buy wins a tie). CF / BF entries are settlement
 * carry-overs: no brokerage, not matched.
 *
 * Returns Map<trade id, { slab, lotSize, intraQty, delQty, intraWaived, brokerage, brokPerUnit, netRate }>.
 */
function computeTradeCalcs(trades, slabs, instruments = []) {
  const result = new Map();
  const groups = new Map();

  for (const t of trades) {
    const inst = findListed(instruments, t.segment, t.script);
    const lotSize = inst?.lotSize ?? 1;
    if (t.tradeType !== 'NRM') {
      result.set(t.id, {
        slab: null, lotSize, intraQty: 0, delQty: t.qty, intraWaived: false,
        brokerage: 0, brokPerUnit: 0, netRate: t.rate,
      });
      continue;
    }
    const key = `${t.date}|${t.clientCode}|${instrumentKey(t)}`;
    const list = groups.get(key);
    if (list) list.push(t);
    else groups.set(key, [t]);
  }

  for (const list of groups.values()) {
    const first = list[0];
    const inst = findListed(instruments, first.segment, first.script);
    const lotSize = inst?.lotSize ?? 1;
    const slab = findSlab(slabs, first.clientCode, first.segment, inst?.symbol ?? first.script);

    const ordered = [...list].sort((a, b) => a.addTime.localeCompare(b.addTime) || a.id - b.id);
    const buys = ordered.filter((t) => t.side === 'B');
    const sells = ordered.filter((t) => t.side === 'S');
    const matched = Math.min(
      buys.reduce((s, t) => s + t.qty, 0),
      sells.reduce((s, t) => s + t.qty, 0)
    );

    const intraBySide = (side) => {
      let left = matched;
      return side.map((t) => {
        const intra = Math.min(t.qty, left);
        left -= intra;
        return { t, intra };
      });
    };
    const buyAlloc = intraBySide(buys);
    const sellAlloc = intraBySide(sells);

    let chargeBuyIntra = true;
    let chargeSellIntra = true;
    if (slab?.higherSideOnly && matched > 0) {
      const buyTurn = buyAlloc.reduce((s, a) => s + a.t.rate * a.intra, 0);
      const sellTurn = sellAlloc.reduce((s, a) => s + a.t.rate * a.intra, 0);
      chargeBuyIntra = buyTurn >= sellTurn;
      chargeSellIntra = !chargeBuyIntra;
    }

    for (const { t, intra } of [...buyAlloc, ...sellAlloc]) {
      const del = t.qty - intra;
      const chargeIntra = t.side === 'B' ? chargeBuyIntra : chargeSellIntra;
      let brokerage = 0;
      if (slab) {
        if (chargeIntra) brokerage += portionBrokerage(slab, 'intra', t.rate, intra, lotSize);
        brokerage += portionBrokerage(slab, 'del', t.rate, del, lotSize);
      }
      const brokPerUnit = t.qty > 0 ? brokerage / t.qty : 0;
      result.set(t.id, {
        slab,
        lotSize,
        intraQty: intra,
        delQty: del,
        intraWaived: intra > 0 && !chargeIntra,
        brokerage,
        brokPerUnit,
        netRate: t.side === 'B' ? t.rate + brokPerUnit : t.rate - brokPerUnit,
      });
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Positions (net-rate averages, MTM at live price or last traded rate)
// ---------------------------------------------------------------------------

function computePositions(trades, calcs, livePrices = {}) {
  const lastTraded = new Map();
  for (const t of [...trades].sort((a, b) => a.addTime.localeCompare(b.addTime) || a.id - b.id)) {
    lastTraded.set(instrumentKey(t), t.rate);
  }

  const map = new Map();
  for (const t of trades) {
    const c = calcs.get(t.id);
    const key = `${t.clientCode}|${instrumentKey(t)}`;
    let p = map.get(key);
    if (!p) {
      p = { sample: t, bq: 0, bn: 0, bg: 0, sq: 0, sn: 0, sg: 0, brk: 0 };
      map.set(key, p);
    }
    const net = (c?.netRate ?? t.rate) * t.qty;
    const gross = t.rate * t.qty;
    if (t.side === 'B') {
      p.bq += t.qty; p.bn += net; p.bg += gross;
    } else {
      p.sq += t.qty; p.sn += net; p.sg += gross;
    }
    p.brk += c?.brokerage ?? 0;
  }

  const out = [];
  for (const [key, p] of map) {
    const t = p.sample;
    const live = livePrices[quoteKey(t)];
    const lastRate = live ?? lastTraded.get(instrumentKey(t)) ?? t.rate;
    const avgBuy = p.bq ? p.bn / p.bq : 0;
    const avgSell = p.sq ? p.sn / p.sq : 0;
    const gAvgBuy = p.bq ? p.bg / p.bq : 0;
    const gAvgSell = p.sq ? p.sg / p.sq : 0;
    const matched = Math.min(p.bq, p.sq);
    const netQty = p.bq - p.sq;
    const unreal = (aBuy, aSell) =>
      netQty > 0 ? (lastRate - aBuy) * netQty : netQty < 0 ? (aSell - lastRate) * -netQty : 0;
    out.push({
      key,
      clientCode: t.clientCode,
      segment: t.segment,
      label: contractLabel(t),
      buyQty: p.bq,
      sellQty: p.sq,
      avgBuy,
      avgSell,
      netQty,
      lastRate,
      live: live != null,
      quoteKey: quoteKey(t),
      realized: (avgSell - avgBuy) * matched,
      mtm: unreal(avgBuy, avgSell),
      grossRealized: (gAvgSell - gAvgBuy) * matched,
      grossMtm: unreal(gAvgBuy, gAvgSell),
      brokerage: p.brk,
    });
  }
  return out.sort((a, b) => a.clientCode.localeCompare(b.clientCode) || a.label.localeCompare(b.label));
}

// ---------------------------------------------------------------------------
// Lots (FIFO) and intraday P&L
// ---------------------------------------------------------------------------

/**
 * Splits a client's equity trades into delivery lots (FIFO) and intraday P&L.
 * NRM = normal executions; BF buys = positions carried in from an earlier month (held
 * from the start of their day, never intraday-matched, no brokerage). CF entries and BF
 * sells are ignored.
 */
function buildEquityLots(trades, calcs) {
  const portions = [];
  const intraday = [];
  const warnings = [];
  const net = (t) => calcs.get(t.id)?.netRate ?? t.rate;
  const catOf = (t) => (t.mtf === undefined ? {} : { mtf: !!t.mtf });

  const byScript = new Map();
  for (const t of trades) {
    if (t.segment !== 'NSEEQ') continue;
    if (t.tradeType === 'CF' || (t.tradeType === 'BF' && t.side !== 'B')) {
      warnings.push(`${t.script} ${t.date}: ${t.tradeType} ${t.side === 'B' ? 'buy' : 'sell'} entry ignored in ledger`);
      continue;
    }
    const list = byScript.get(t.script);
    if (list) list.push(t);
    else byScript.set(t.script, [t]);
  }

  for (const [script, list] of byScript) {
    const open = []; // FIFO of { t, qty }
    const sorted = [...list].sort((a, b) => a.date.localeCompare(b.date) || a.addTime.localeCompare(b.addTime) || a.id - b.id);
    const dates = [...new Set(sorted.map((t) => t.date))];
    for (const date of dates) {
      const day = sorted.filter((t) => t.date === date);
      // Brought-forward positions are already held when the day starts.
      for (const t of day) if (t.tradeType === 'BF') open.push({ t, qty: t.qty });
      const buys = day.filter((t) => t.side === 'B' && t.tradeType !== 'BF').map((t) => ({ t, qty: t.qty }));
      for (const sell of day.filter((t) => t.side === 'S')) {
        let left = sell.qty;
        // 1. Same-day buys first: intraday.
        for (const b of buys) {
          const m = Math.min(b.qty, left);
          if (!m) continue;
          intraday.push({ script, date, pnl: (net(sell) - net(b.t)) * m });
          b.qty -= m;
          left -= m;
        }
        // 2. Then the oldest held lots.
        while (left > 0 && open.length) {
          const lot = open[0];
          const m = Math.min(lot.qty, left);
          portions.push({
            script, buyDate: lot.t.date, qty: m, netBuyRate: net(lot.t), fullPayment: !!lot.t.fullPayment,
            closeDate: date, sellNetRate: net(sell), ...catOf(lot.t),
          });
          lot.qty -= m;
          left -= m;
          if (!lot.qty) open.shift();
        }
        if (left > 0) warnings.push(`${script} ${date}: sold ${left} more than held — ignored in ledger`);
      }
      for (const b of buys) if (b.qty > 0) open.push(b);
    }
    for (const lot of open) {
      portions.push({
        script, buyDate: lot.t.date, qty: lot.qty, netBuyRate: net(lot.t), fullPayment: !!lot.t.fullPayment,
        closeDate: null, sellNetRate: null, ...catOf(lot.t),
      });
    }
  }
  return { portions, intraday, warnings };
}

// ---------------------------------------------------------------------------
// Client money ledger with interest on the funded amount
// ---------------------------------------------------------------------------
//
//   Margin used  = value of open delivery lots: net buy cost, or the settlement price once
//                  carried through a month-end. A lot counts from its buy day and is
//                  released on its sell day. Intraday trades use no margin.
//   Client money = opening ± deposits / withdrawals / journals
//                  + P&L and MTM posted at month-ends − interest posted at month-ends.
//                  Trade P&L is NOT counted during the month.
//   Funded       = max(0, margin used − client money)
//   Interest/day = funded × interest % ÷ 365, every calendar day.

const round2 = (n) => Math.round(n * 100) / 100;
const fmtQty = (n) => n.toLocaleString('en-IN');
const fmtRate = (n) => n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const dmy = (d) => d.split('-').reverse().join('-');

const ENTRY_LABEL = {
  DEPOSIT: 'Deposit', WITHDRAWAL: 'Withdrawal / Payout', JOURNAL_CR: 'Journal Cr', JOURNAL_DR: 'Journal Dr',
};
const ROW_ORDER = ['PNL', 'MTM', 'INTEREST', 'REVALUE', 'DEPOSIT', 'JOURNAL_CR', 'WITHDRAWAL', 'JOURNAL_DR', 'BUY', 'RELEASE'];

/** Statement and interest for one client, up to `asOf` (inclusive). */
function computeClientLedger(account, trades, calcs, entries, allSettlements, asOf) {
  const mine = trades.filter((t) => t.clientCode === account.code && t.date <= asOf);
  const { portions, intraday, warnings } = buildEquityLots(mine, calcs);
  const myEntries = entries.filter((e) => e.clientCode === account.code && e.date <= asOf);
  // A month-end is billed at the end of the month's last day (the day before its 1st-of-month key).
  const postDate = (s) => addDays(s.settleDate, -1);
  const settlements = allSettlements
    .filter((s) => s.segment !== 'NCDEX' && postDate(s) <= asOf)
    .sort((a, b) => a.settleDate.localeCompare(b.settleDate));
  const rate = account.interestPct / 100 / 365;
  // Two interest rates (equity accounts): approved (MTF) scripts at interestPct, non-approved
  // at interestNonPct. The funded amount is split across the two in proportion to each
  // category's margin. With one rate (Trade Terminal accounts, or equal rates) the original
  // single-rate path runs unchanged. A debit balance with nothing held is charged at the
  // approved rate.
  // Equity accounts always track the split (sharing needs interest per category); the
  // proportional formula only runs when the two rates differ, so equal rates give exactly
  // the single-rate interest.
  const split = account.interestNonPct !== undefined;
  const twoRates = split && account.interestNonPct !== account.interestPct;
  const rateNon = split ? account.interestNonPct / 100 / 365 : rate;
  const catOfP = (p) => (p.mtf === false ? 'non' : 'mtf');

  // --- Settlement P&L per portion: MTM at each bhav, realized at the settlement after the sale.
  const realizedAt = new Map(); // settlement index → realized P&L
  const mtmAt = new Map();
  const missing = new Map();
  let pendingPnl = 0;
  const add = (m, i, v) => m.set(i, (m.get(i) ?? 0) + v);
  for (const p of portions) {
    let carry = p.netBuyRate;
    settlements.forEach((s, i) => {
      const heldAtPrice = p.buyDate <= s.priceDate && (p.closeDate === null || p.closeDate > s.priceDate);
      if (!heldAtPrice) return;
      const price = s.prices[p.script];
      if (!(price > 0)) {
        if (!missing.has(i)) missing.set(i, new Set());
        missing.get(i).add(p.script);
        return;
      }
      add(mtmAt, i, (price - carry) * p.qty);
      carry = price;
    });
    if (p.closeDate !== null) {
      const pnl = (p.sellNetRate - carry) * p.qty;
      const i = settlements.findIndex((s) => s.priceDate >= p.closeDate);
      if (i >= 0) add(realizedAt, i, pnl);
      else pendingPnl += pnl;
    }
  }
  for (const x of intraday) {
    const i = settlements.findIndex((s) => s.priceDate >= x.date);
    if (i >= 0) add(realizedAt, i, x.pnl);
    else pendingPnl += x.pnl;
  }

  // --- Effective-dated changes (settlement rows are added during the walk).
  const changes = [];
  const revalue = new Map(); // settlement index → margin change on its 1st
  const revalueNon = new Map(); // same, non-approved scripts (two-rate accounts only)
  for (const p of portions) {
    if (p.fullPayment) continue;
    let amount = p.netBuyRate * p.qty;
    changes.push({
      date: p.buyDate, kind: 'BUY', money: 0, margin: amount, cat: catOfP(p),
      particulars: `BUY ${fmtQty(p.qty)} ${p.script} @ ${fmtRate(p.netBuyRate)} (net)`,
    });
    // Still held on a settlement's 1st: reopens at that settlement's price.
    settlements.forEach((s, i) => {
      const price = s.prices[p.script];
      const held = p.buyDate <= s.priceDate && (p.closeDate === null || p.closeDate >= s.settleDate);
      if (!held || !(price > 0) || s.settleDate > asOf) return;
      add(split && catOfP(p) === 'non' ? revalueNon : revalue, i, price * p.qty - amount);
      amount = price * p.qty;
    });
    if (p.closeDate !== null && p.closeDate <= asOf) {
      changes.push({
        date: p.closeDate, kind: 'RELEASE', money: 0, margin: -amount, cat: catOfP(p),
        particulars: `SOLD ${fmtQty(p.qty)} ${p.script} @ ${fmtRate(p.sellNetRate)} (net) — margin released`,
      });
    }
  }
  for (const [map, cat] of [[revalue, 'mtf'], [revalueNon, 'non']]) {
    map.forEach((delta, i) => {
      const s = settlements[i];
      if (Math.abs(delta) < 0.005) return;
      const which = split ? (cat === 'non' ? ' — non-approved' : ' — approved') : '';
      changes.push({
        date: s.settleDate, kind: 'REVALUE', money: 0, margin: delta, cat,
        particulars: `Open positions reopened at settlement price (bhav ${dmy(s.priceDate)})${which}`,
      });
    });
  }
  for (const e of myEntries) {
    const credit = e.kind === 'DEPOSIT' || e.kind === 'JOURNAL_CR';
    changes.push({
      date: e.date, kind: e.kind, margin: 0, money: credit ? e.amount : -e.amount,
      particulars: `${ENTRY_LABEL[e.kind]}${e.narration ? ` — ${e.narration}` : ''}`,
    });
  }
  changes.sort((a, b) => a.date.localeCompare(b.date) || ROW_ORDER.indexOf(a.kind) - ROW_ORDER.indexOf(b.kind));

  const opening = account.openingType === 'Cr' ? account.openingBalance : -account.openingBalance;
  const firstDate = [changes[0]?.date, settlements[0] && postDate(settlements[0])].filter(Boolean).sort()[0];
  const rows = [];
  const summaries = [];
  let money = opening;
  let margin = 0;
  let periodInterest = 0;
  let postedInterest = 0;
  let marginMtf = 0; // two-rate accounts: margin per category
  let marginNon = 0;
  let periodMtf = 0;
  let periodNon = 0;
  let periodFrom = firstDate ?? asOf;
  let ci = 0;
  let si = 0;

  const push = (date, kind, particulars, moneyDelta, marginDelta, cat) => {
    money += moneyDelta;
    margin += marginDelta;
    if (Math.abs(margin) < 0.005) margin = 0;
    if (split) {
      if (cat === 'non') marginNon += marginDelta; else marginMtf += marginDelta;
      if (Math.abs(marginNon) < 0.005) marginNon = 0;
      if (Math.abs(marginMtf) < 0.005) marginMtf = 0;
    }
    rows.push({
      date, kind, particulars,
      debit: moneyDelta < 0 ? -moneyDelta : 0, credit: moneyDelta > 0 ? moneyDelta : 0, marginChange: marginDelta,
      money, margin, funded: Math.max(0, margin - money), days: 0, interest: 0, ...(split ? { marginNon } : {}),
    });
  };

  if (firstDate) {
    push(firstDate, 'BF', 'Opening balance', 0, 0);
    rows[0].money = money = opening;
    rows[0].credit = opening > 0 ? opening : 0;
    rows[0].debit = opening < 0 ? -opening : 0;
    rows[0].funded = Math.max(0, margin - money);

    for (let d = firstDate; d <= asOf; d = addDays(d, 1)) {
      // Month boundary: a b/f row so each month's interest stays within that month.
      if (d.endsWith('-01') && d !== firstDate) push(d, 'BF', 'Balance brought forward', 0, 0);
      while (ci < changes.length && changes[ci].date === d) {
        const c = changes[ci++];
        push(d, c.kind, c.particulars, c.money, c.margin, c.cat);
      }
      let dayInterest;
      if (!split) dayInterest = Math.max(0, margin - money) * rate;
      else {
        const funded = Math.max(0, margin - money);
        const fm = Math.max(0, marginMtf);
        const fn = Math.max(0, marginNon);
        const shareNon = fm + fn > 0 ? fn / (fm + fn) : 0;
        if (twoRates) {
          const dNon = funded * shareNon * rateNon;
          const dMtf = funded * (1 - shareNon) * rate;
          periodMtf += dMtf;
          periodNon += dNon;
          dayInterest = dMtf + dNon;
        } else {
          dayInterest = funded * rate;
          periodNon += dayInterest * shareNon;
          periodMtf += dayInterest * (1 - shareNon);
        }
      }
      periodInterest += dayInterest;
      const last = rows[rows.length - 1];
      last.days += 1;
      last.interest += dayInterest;

      // Month-end billing, after the day's interest: P&L, MTM @ bhav and the period's interest.
      // The new balance applies from the next day (the 1st).
      while (si < settlements.length && postDate(settlements[si]) === d) {
        const st = settlements[si];
        const realized = realizedAt.get(si) ?? 0;
        const mtm = mtmAt.get(si) ?? 0;
        const interest = round2(periodInterest);
        if (realized) push(d, 'PNL', `Settlement ${dmy(d)}: P&L on trades closed till ${dmy(st.priceDate)}`, round2(realized), 0);
        if (mtm) push(d, 'MTM', `Settlement ${dmy(d)}: MTM of open positions @ bhav ${dmy(st.priceDate)}`, round2(mtm), 0);
        const at = twoRates ? `${account.interestPct}% approved / ${account.interestNonPct}% non-approved` : `${account.interestPct}%`;
        if (interest) push(d, 'INTEREST', `Interest ${dmy(periodFrom)} to ${dmy(d)} @ ${at}`, -interest, 0);
        summaries.push({
          settlement: st, periodFrom, periodTo: d, realized: round2(realized), mtm: round2(mtm), interest,
          missingPrices: [...(missing.get(si) ?? [])].sort(),
          ...(split ? { interestMtf: round2(periodMtf), interestNon: round2(periodNon) } : {}),
        });
        postedInterest += interest;
        periodInterest = 0;
        periodMtf = 0;
        periodNon = 0;
        periodFrom = addDays(d, 1);
        si++;
      }
    }
  }

  return {
    account, rows, settlements: summaries, postedInterest, accruedInterest: periodInterest, pendingPnl,
    money, margin, funded: Math.max(0, margin - money), warnings,
    ...(split ? { marginMtf, marginNon, accruedInterestMtf: periodMtf, accruedInterestNon: periodNon } : {}),
  };
}

/**
 * Trades as they stand after the last month-end on or before `asOf` (for live holdings
 * and reports), so P&L runs from the last month-end: trades before it are replaced by
 * one BF buy per lot still held, at the price it was carried at (bhav close, else
 * earlier carry). Carried positions have no brokerage. A month-end billed on `asOf`
 * itself is not applied, so a billing-day report shows that month's P&L.
 */
function carryToSettlement(trades, calcs, allSettlements, asOf) {
  const monthly = allSettlements
    .filter((s) => s.settleDate <= asOf && s.segment !== 'NCDEX')
    .sort((a, b) => a.settleDate.localeCompare(b.settleDate));
  const since = monthly[monthly.length - 1] ?? null;
  if (!since) return { trades, calcs, since };

  const outCalcs = new Map(calcs);
  const carried = [];
  let id = 0;
  const carry = (clientCode, script, qty, rate, date, fullPayment = false) => {
    const t = {
      id: --id, ot: 'T', date, valan: '', segment: 'NSEEQ', script, option: '', strike: 0, tradeType: 'BF', side: 'B', lot: qty, qty, rate,
      clientCode, fullPayment, user: '', ip: '', addTime: `${date} 00:00:00`,
    };
    carried.push(t);
    outCalcs.set(t.id, { slab: null, lotSize: 1, intraQty: 0, delQty: qty, intraWaived: false, brokerage: 0, brokPerUnit: 0, netRate: rate });
  };

  const settledEq = (t) => t.segment === 'NSEEQ' && t.date < since.settleDate;
  const eqByClient = new Map();
  for (const t of trades) if (settledEq(t)) eqByClient.set(t.clientCode, [...(eqByClient.get(t.clientCode) ?? []), t]);
  for (const [clientCode, list] of eqByClient) {
    for (const p of buildEquityLots(list, calcs).portions) {
      if (p.closeDate !== null) continue;
      let price = p.netBuyRate;
      for (const s of monthly) if (p.buyDate <= s.priceDate && s.prices[p.script] > 0) price = s.prices[p.script];
      carry(clientCode, p.script, p.qty, price, since.settleDate, p.fullPayment);
    }
  }
  return { trades: [...trades.filter((t) => !settledEq(t)), ...carried], calcs: outCalcs, since };
}

// ---------------------------------------------------------------------------
// Market hours and day LIMIT orders
// ---------------------------------------------------------------------------

const SESSION = ['09:15', '15:30']; // NSE cash market, IST

/** Today's date (YYYY-MM-DD) and time (HH:MM) in India, whatever the server's time zone. */
function istNow(at = new Date()) {
  const ist = new Date(at.getTime() + 5.5 * 3600_000);
  return { date: ist.toISOString().slice(0, 10), time: ist.toISOString().slice(11, 16), weekday: ist.getUTCDay() };
}

/** Normal NSE cash session open now (Mon–Fri, IST)? Exchange holidays are checked by the caller. */
function marketOpen(at = new Date()) {
  const { time, weekday } = istNow(at);
  return weekday >= 1 && weekday <= 5 && time >= SESSION[0] && time < SESSION[1];
}

/**
 * Touch-style limit: waits until the LTP comes to the limit price from the side it was
 * on when placed — rises to it (LTP at placement below the limit) or falls to it
 * (above). Returns the LTP that touched, else null.
 */
function limitTouched(o, ltp) {
  if (!(ltp > 0)) return null;
  const rising = o.refPrice != null ? o.refPrice <= o.limitPrice : o.side === 'S';
  return rising ? (ltp >= o.limitPrice ? ltp : null) : (ltp <= o.limitPrice ? ltp : null);
}

module.exports = {
  addDays,
  daysInclusive,
  findListed,
  instrumentKey,
  quoteKey,
  contractLabel,
  findSlab,
  portionBrokerage,
  computeTradeCalcs,
  computePositions,
  buildEquityLots,
  computeClientLedger,
  carryToSettlement,
  istNow,
  marketOpen,
  limitTouched,
  round2,
};
