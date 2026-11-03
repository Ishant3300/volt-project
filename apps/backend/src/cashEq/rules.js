'use strict';

// Equity waterfall rules — pure functions (no database).
//
// Each level is capped by the level above it:
//   • per-script and total limits   ≤ parent's   (limits apply per client, not to a tree total)
//   • brokerage (intraday, carry, minimum per share) ≥ parent's, same mode (PCT/FIX);
//     "higher side only" (cheaper) only if the parent has it too
//   • interest % per year           ≥ parent's
//   • sharing % (masters)            ≤ parent's, like F&O pnl_sharing / brokerage_sharing
// Top-level equity masters sit under admin: only the basic checks apply.

const SHARE_KEYS = ['pnl_share', 'brokerage_share', 'interest_share'];

const lakh = (n) => {
  if (!Number.isFinite(n)) return String(n);
  if (n >= 1e7) return `${+(n / 1e7).toFixed(2)} Cr`;
  if (n >= 1e5) return `${+(n / 1e5).toFixed(2)} L`;
  return n.toLocaleString('en-IN');
};

const num = (v) => (v === '' || v === null || v === undefined ? NaN : Number(v));

/** Normalise request values to the stored shape (numbers, booleans, upper-case mode). */
function normalise(input, { master }) {
  const b = input.brokerage || {};
  const out = {
    per_script_limit: num(input.per_script_limit),
    total_limit: num(input.total_limit),
    interest_pct: num(input.interest_pct),
    brokerage: {
      mode: String(b.mode || 'PCT').toUpperCase(),
      intraday: num(b.intraday ?? 0),
      carry: num(b.carry ?? 0),
      min_rate: num(b.min_rate ?? 0),
      higher_side_only: b.higher_side_only === true || b.higher_side_only === 'true',
    },
  };
  if (master) for (const k of SHARE_KEYS) out[k] = num(input[k]);
  return out;
}

/** Basic sanity of one account's settings. */
function checkBasics(acc, { master }) {
  const errs = [];
  for (const k of ['per_script_limit', 'total_limit', 'interest_pct']) {
    if (!Number.isFinite(acc[k]) || acc[k] < 0) errs.push(`${k.replace(/_/g, ' ')} must be a number, 0 or more`);
  }
  if (Number.isFinite(acc.per_script_limit) && Number.isFinite(acc.total_limit) && acc.per_script_limit > acc.total_limit) {
    errs.push(`Per-script limit (${lakh(acc.per_script_limit)}) can't be above the total limit (${lakh(acc.total_limit)})`);
  }
  if (acc.interest_pct > 100) errs.push('Interest % must be 100 or less');
  const b = acc.brokerage;
  if (!['PCT', 'FIX'].includes(b.mode)) errs.push('Brokerage mode must be PCT or FIX');
  for (const k of ['intraday', 'carry', 'min_rate']) {
    if (!Number.isFinite(b[k]) || b[k] < 0) errs.push(`Brokerage ${k.replace('_', ' ')} must be a number, 0 or more`);
  }
  if (b.mode === 'PCT' && (b.intraday > 5 || b.carry > 5)) errs.push('Brokerage % looks wrong (more than 5 %)');
  if (master) {
    for (const k of SHARE_KEYS) {
      if (!Number.isFinite(acc[k]) || acc[k] < 0 || acc[k] > 100) errs.push(`${k.replace(/_/g, ' ')} must be between 0 and 100`);
    }
  }
  return errs;
}

/** `child` against the master directly above it (null = top level, under admin). */
function checkAgainstParent(child, parent, { master }) {
  const errs = checkBasics(child, { master });
  if (!parent || errs.length) return errs;
  const pb = parent.brokerage || {};
  const cb = child.brokerage;
  if (child.per_script_limit > parent.per_script_limit) {
    errs.push(`Per-script limit can't be above ${lakh(parent.per_script_limit)} (${parent.username})`);
  }
  if (child.total_limit > parent.total_limit) {
    errs.push(`Total limit can't be above ${lakh(parent.total_limit)} (${parent.username})`);
  }
  if (child.interest_pct < parent.interest_pct) {
    errs.push(`Interest can't be below ${parent.interest_pct} % (${parent.username})`);
  }
  if (cb.mode !== (pb.mode || 'PCT')) {
    errs.push(`Brokerage must be ${pb.mode || 'PCT'} like ${parent.username}`);
  } else {
    const unit = cb.mode === 'PCT' ? ' %' : ' per share';
    if (cb.intraday < (pb.intraday || 0)) errs.push(`Intraday brokerage can't be below ${pb.intraday}${unit} (${parent.username})`);
    if (cb.carry < (pb.carry || 0)) errs.push(`Carry forward brokerage can't be below ${pb.carry}${unit} (${parent.username})`);
    if (cb.min_rate < (pb.min_rate || 0)) errs.push(`Minimum brokerage can't be below ${pb.min_rate} per share (${parent.username})`);
  }
  if (cb.higher_side_only && !pb.higher_side_only) {
    errs.push(`"Higher side only" can't be on: ${parent.username} charges both sides`);
  }
  if (master) {
    for (const k of SHARE_KEYS) {
      if (child[k] > parent[k]) errs.push(`${k.replace(/_/g, ' ')} can't be above ${parent[k]} % (${parent.username})`);
    }
  }
  return errs;
}

/**
 * A master's new settings against everyone directly below it (sub-masters and clients):
 * a master can't be changed to a cap below — or a floor above — what it already gave out.
 */
function checkAgainstChildren(parent, children) {
  const errs = [];
  for (const c of children) {
    const isMaster = c.pnl_share !== undefined;
    const e = checkAgainstParent(
      { ...c, brokerage: { mode: 'PCT', intraday: 0, carry: 0, min_rate: 0, higher_side_only: false, ...(c.brokerage || {}) } },
      parent,
      { master: isMaster }
    );
    for (const m of e) errs.push(`${c.username}: ${m.replace(/ \([^)]*\)$/, '')}`);
  }
  return errs;
}

/** Trade Terminal slab (engine.js) from a client's brokerage. */
function toSlab(client) {
  const b = client.brokerage || {};
  const pct = b.mode !== 'FIX';
  return {
    id: 1, clientCode: String(client._id), segment: 'NSEEQ', scriptWise: false, script: '',
    mode: pct ? 'PCT' : 'FIX',
    delPct: pct ? b.carry || 0 : 0, intraPct: pct ? b.intraday || 0 : 0,
    fixDel: pct ? 0 : b.carry || 0, fixIntra: pct ? 0 : b.intraday || 0,
    higherSideOnly: !!b.higher_side_only, minRate: pct ? b.min_rate || 0 : 0, minPct: 0, minPctOnDel: 0,
  };
}

/** Trade Terminal account (engine.js) from a client. */
function toAccount(client) {
  return {
    code: String(client._id),
    openingBalance: client.opening_balance || 0,
    openingType: client.opening_type === 'Dr' ? 'Dr' : 'Cr',
    interestPct: client.interest_pct || 0,
  };
}

/** Equity usernames always start with EQ, so they stand apart from F&O ones. */
const USERNAME_RE = /^EQ[A-Z0-9]{3,14}$/;

module.exports = {
  SHARE_KEYS, USERNAME_RE, lakh, normalise, checkBasics, checkAgainstParent, checkAgainstChildren, toSlab, toAccount,
};
