'use strict';

/**
 * Practice (paper) trading mode — see docs/practice-trading.md.
 *
 * Set only on the separate practice backend process. When PRACTICE_MODE is not
 * '1' (the live backend) every check below is false and no behaviour changes.
 */
const PRACTICE = process.env.PRACTICE_MODE === '1';

module.exports = Object.freeze({
  PRACTICE,
  // Simulated prices step every this many minutes (IST clock).
  STEP_MIN: Number(process.env.PRACTICE_STEP_MIN || 30),
  // Live database — read-only, only for copying reference data (contracts).
  LIVE_MONGO_URI: process.env.LIVE_MONGO_URI || '',
});
