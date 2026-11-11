'use strict';

/**
 * Which of a broker link's rates applies to a fill (owner, 12 Nov 2026).
 * TRACKING ONLY — used by the broker statement, the old brokerage-share view
 * and the limits; nothing in the ledger, weekly, settlement or brokerage code
 * reads it.
 *
 * A link's rates[] may hold, per segment:
 *   { segment, type, value }                     the whole segment
 *   { segment, type, value, category: 'INDEX' }  NFO-FUT / NFO-OPT Index scripts
 *   { segment, type, value, category: 'STOCK' }  NFO-FUT / NFO-OPT Stock scripts
 *   { segment, type, value, script: 'GOLD' }     one script (MCX-FUT / MCX-OPT)
 * The most specific one that matches the fill wins: script, then category,
 * then the whole segment. Index vs Stock is the same rule the brokerage
 * settings use (constants/nfoIndexUnderlyings).
 */

const { categoryForNfoScript } = require('../constants/nfoIndexUnderlyings');

/** Segments whose broker rate can be split Index / Stock, and per script — same as the app's Customize. */
const CATEGORY_SEGMENTS = new Set(['NFO-FUT', 'NFO-OPT']);
const SCRIPT_SEGMENTS = new Set(['MCX-FUT', 'MCX-OPT']);

const norm = (s) => {
  const v = String(s || '').trim().toUpperCase();
  return v === 'GLOBAL' ? 'INDICES' : v;
};
const upper = (s) => (s == null || s === '' ? null : String(s).trim().toUpperCase());

/** 'script' | 'category' | 'segment' */
function rateScope(r) {
  if (upper(r && r.script)) return 'script';
  if (upper(r && r.category)) return 'category';
  return 'segment';
}

/** A stable key: one rate per (segment, category, script). */
function rateKey(r) {
  return `${norm(r && r.segment)}|${upper(r && r.category) || ''}|${upper(r && r.script) || ''}`;
}

/** The rate for a fill of `rawName` in `segment`, or null. */
function pickRate(rates, segment, rawName) {
  const seg = norm(segment);
  const name = upper(rawName);
  const mine = (rates || []).filter((r) => norm(r.segment) === seg);
  if (mine.length === 0) return null;
  if (name) {
    const byScript = mine.find((r) => upper(r.script) === name);
    if (byScript) return byScript;
    const cat = categoryForNfoScript(seg, name);
    if (cat) {
      const byCat = mine.find((r) => !upper(r.script) && upper(r.category) === cat);
      if (byCat) return byCat;
    }
  }
  return mine.find((r) => !upper(r.script) && !upper(r.category)) || null;
}

module.exports = { CATEGORY_SEGMENTS, SCRIPT_SEGMENTS, rateScope, rateKey, pickRate };
