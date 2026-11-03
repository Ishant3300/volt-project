'use strict';

// Equity on/off switch, read from Redis on every call (5-second cache) — no restart needed.
//
//   redis6-cli SET cashEq:enabled 1        → equity on
//   redis6-cli DEL cashEq:enabled          → equity off: every /api/cash-eq route answers
//                                            404 and equity logins say "Invalid credentials"
//   redis6-cli SET cashEq:minAppBuild 60   → app builds from 60 may sign equity accounts in
//                                            (not set: equity accounts sign in on the web only)
//
// Redis unavailable → off (fails closed).

const redisService = require('../services/redisService');

const CACHE_MS = 5000;
const cache = new Map(); // key -> { value, at }

async function read(key) {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.value;
  let value = null;
  try {
    const client = redisService.getClient();
    if (client && redisService.isAvailable()) value = await client.get(key);
  } catch (_) {
    value = null;
  }
  cache.set(key, { value, at: Date.now() });
  return value;
}

async function enabled() {
  return (await read('cashEq:enabled')) === '1';
}

const APP_UA = /^(Volt|Apex|Velo)\/[\d.]+\+(\d+)/i;

/** Web portal: always. App: only builds that know equity accounts (cashEq:minAppBuild). */
async function appAllowed(req) {
  const m = APP_UA.exec(req.get?.('user-agent') || req.headers?.['user-agent'] || '');
  if (!m) return true;
  const min = Number(await read('cashEq:minAppBuild'));
  return Number.isInteger(min) && min > 0 && Number(m[2]) >= min;
}

function _clearCache() {
  cache.clear();
}

module.exports = { enabled, appAllowed, _clearCache };
