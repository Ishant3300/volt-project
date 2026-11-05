'use strict';

/**
 * Server-side force update (2 Nov 2026).
 *
 * The app's own force-update check fails open (a slow or failed fetch of
 * `<brand>-version.json` lets the user in) and only runs on cold start /
 * resume, so an old Android build could still log in and trade. This refuses
 * logins and order changes from an Android app build older than the published
 * one — the same `<brand>-version.json` the in-app updater reads, so every
 * future force update is enforced here automatically.
 *
 * Only Android app requests are checked (User-Agent "Volt/1.0.52+55 (Android …"),
 * never the web portal or iPhones (App Store builds have their own numbers).
 * If the version file can't be read, everything is allowed.
 */
const fs = require('fs');
const path = require('path');

const DOWNLOADS_DIR = process.env.APP_DOWNLOADS_DIR || '/var/www/downloads';
const CACHE_MS = 60 * 1000;
// Android and (since 5 Nov 2026) iPhone: an iOS build older than the file's
// ios_build is refused the same way — every iOS update is a force update too.
const UA_RE = /^(Volt|Apex|Velo)\/[\d.]+\+(\d+)\s*\((Android|iOS)/i;
const LOGIN_RE = /^\/api\/auth\/(?:(?:user|admin|master)\/)?login\/?$/;
const TRADE_RE = /^\/api\/trade(?:\/|$)/;

const cache = new Map(); // `${brand}|${platform}` -> { build, at }
const logged = new Map(); // `${ip}|${build}` -> last log time

/** Published minimum build: `build` for Android, `ios_build` for iPhone; null = no enforcement. */
function publishedBuild(brand, platform = 'android') {
  const cacheKey = `${brand}|${platform}`;
  const hit = cache.get(cacheKey);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.build;
  let build = null;
  try {
    const body = JSON.parse(fs.readFileSync(path.join(DOWNLOADS_DIR, `${brand}-version.json`), 'utf8'));
    const value = platform === 'ios' ? body.ios_build : body.build;
    if (Number.isInteger(value) && value > 0) build = value;
  } catch (_) {
    build = null; // missing/unreadable → no enforcement for this brand
  }
  cache.set(cacheKey, { build, at: Date.now() });
  return build;
}

function minAppVersion(req, res, next) {
  try {
    const guarded = (req.method === 'POST' && LOGIN_RE.test(req.path))
      || (req.method !== 'GET' && req.method !== 'OPTIONS' && TRADE_RE.test(req.path));
    if (!guarded) return next();

    const m = UA_RE.exec(req.get('user-agent') || '');
    if (!m) return next();
    const brand = m[1].toLowerCase();
    const build = Number(m[2]);
    const platform = m[3].toLowerCase() === 'ios' ? 'ios' : 'android';
    const required = publishedBuild(brand, platform);
    if (!required || build >= required) return next();

    const key = `${req.ip}|${build}`;
    if (Date.now() - (logged.get(key) || 0) > 10 * 60 * 1000) {
      logged.set(key, Date.now());
      console.log(`📵 [MinAppVersion] Refused ${req.method} ${req.path} from ${brand} build ${build} (< ${required}) ip=${req.ip}`);
    }
    return res.status(403).json({
      success: false,
      code: 'APP_UPDATE_REQUIRED',
      message: platform === 'ios'
        ? 'Please update the app from the App Store to continue.'
        : 'Please update the app to the latest version to continue. Close the app, open it again and tap Update.',
      data: null,
    });
  } catch (_) {
    return next();
  }
}

module.exports = minAppVersion;
module.exports._test = { UA_RE, LOGIN_RE, TRADE_RE, cache };
