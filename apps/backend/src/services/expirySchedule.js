'use strict';

/**
 * Pure date logic for the contract-expiry rules (config/expiryRules.js) —
 * no DB, no clock — so every rule can be checked against real calendars in
 * unit tests. expiryActionService.js feeds it contracts and holidays.
 *
 * All dates are UTC-midnight Date objects standing for India calendar days,
 * the same convention as utils/settlementDates.js and KiteInstrument.expiry.
 */

const { addUtcDays, dateKey, isTradingDay, onOrBeforeTradingDay, previousTradingDay } = require('../utils/settlementDates');

const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

/** `n` working days before `expiry` (0 = the expiry day itself). */
function workingDaysBefore(expiry, n, holidays) {
  let day = new Date(expiry);
  for (let i = 0; i < n; i++) day = previousTradingDay(day, holidays);
  return day;
}

/** Monday of the expiry's week, or the working day before it if that Monday is a holiday. */
function expiryWeekMonday(expiry, holidays) {
  const back = (expiry.getUTCDay() + 6) % 7; // Mon=0 … Sun=6
  return onOrBeforeTradingDay(addUtcDays(expiry, -back), holidays);
}

function ruleDate(rule, expiry, holidays) {
  if (!rule) return null;
  if (rule.type === 'WORKING_DAYS_BEFORE') return workingDaysBefore(expiry, rule.days, holidays);
  if (rule.type === 'EXPIRY_WEEK_MONDAY') return expiryWeekMonday(expiry, holidays);
  throw new Error(`Unknown expiry rule type: ${rule.type}`);
}

/** An IST wall-clock time ('HH:MM') on an India calendar day → absolute instant. */
function istInstant(day, hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), h, m) - IST_OFFSET_MS);
}

/** One minute after `hhmm`. */
function plusOneMinute(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  const total = h * 60 + m + 1;
  return `${String(Math.floor(total / 60) % 24).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
}

/**
 * Plan every OPEN/CUT action for one rule group.
 *
 * @param {object} group - one entry of expiryRules.GROUPS
 * @param {Array<{name:string, expiry:Date}>} contracts - the group's future
 *   contracts (any order; one entry per name+expiry is enough)
 * @param {Set<string>|null} holidays - 'YYYY-MM-DD' keys; null/empty = weekdays only
 * @param {{ effectiveFrom: string, openTime: string }} opts
 * @returns {Array<object>} actions, each with a stable `key`
 */
function planGroup(group, contracts, holidays, { effectiveFrom, openTime }) {
  const byName = new Map();
  for (const c of contracts) {
    if (!c.expiry) continue;
    const name = String(c.name).toUpperCase();
    if (!byName.has(name)) byName.set(name, new Map());
    byName.get(name).set(dateKey(c.expiry), new Date(c.expiry));
  }

  // Current expiry → names that have a contract on it, and each name's next contract.
  const byExpiry = new Map();
  for (const [name, expiries] of byName) {
    const sorted = [...expiries.values()].sort((a, b) => a - b);
    sorted.forEach((expiry, i) => {
      const key = dateKey(expiry);
      if (!byExpiry.has(key)) byExpiry.set(key, { expiry, names: [], targets: [] });
      const entry = byExpiry.get(key);
      entry.names.push(name);
      if (sorted[i + 1]) entry.targets.push({ name, expiry: sorted[i + 1] });
    });
  }

  const actions = [];
  for (const [expiryKey, { expiry, names, targets }] of byExpiry) {
    const cutDay = ruleDate(group.cut, expiry, holidays);
    const openDay = group.continuous ? null : ruleDate(group.open, expiry, holidays);

    if (openDay && targets.length > 0 && dateKey(openDay) >= effectiveFrom) {
      actions.push({
        key: `${group.key}|OPEN|${expiryKey}`,
        kind: 'OPEN',
        current_expiry: expiry,
        action_date: dateKey(openDay),
        execute_at: istInstant(openDay, openTime),
        names: [...names].sort(),
        targets: targets.sort((a, b) => a.name.localeCompare(b.name)),
      });
    }
    if (cutDay && dateKey(cutDay) >= effectiveFrom) {
      actions.push({
        key: `${group.key}|CUT|${expiryKey}`,
        kind: 'CUT',
        current_expiry: expiry,
        action_date: dateKey(cutDay),
        execute_at: istInstant(cutDay, plusOneMinute(group.closeTime)),
        names: [...names].sort(),
        targets: [],
      });
    }
  }
  return actions.sort((a, b) => a.execute_at - b.execute_at || a.key.localeCompare(b.key));
}

module.exports = {
  planGroup,
  workingDaysBefore,
  expiryWeekMonday,
  istInstant,
  plusOneMinute,
  isTradingDay,
};
