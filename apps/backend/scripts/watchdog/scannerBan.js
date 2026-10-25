'use strict';

/**
 * Auto-ban of secret-file scanners (25 Oct 2026). An IP that makes
 * THRESHOLD secret-file probes (lib.isProbe — ".env", ".git/", "wp-config"…
 * anywhere in the URL, query included) within WINDOW_MS is denied by nginx
 * for BAN_MS. nginx itself already refuses those URLs (return 444); the ban
 * just shuts the rest of the scan out too. No firewall involved: nginx reads
 * DENY_FILE (`include`d in the apexlive-api server block) and is reloaded
 * gracefully — no dropped connections. Normal clients never request these
 * URLs, so they cannot trip it; the old forwarding server, this server,
 * localhost and private addresses are never banned (WATCHDOG_BAN_IGNORE adds
 * more, comma-separated).
 */

const { execFileSync } = require('child_process');

const DENY_FILE = '/etc/nginx/blocked-scanners.conf';
const WINDOW_MS = 10 * 60_000;
const THRESHOLD = 5;
const BAN_MS = 7 * 24 * 3600_000;
const ALWAYS_ALLOW = ['127.0.0.1', '::1', '13.207.113.128', '13.232.214.61'];

function isIp(ip) {
  const s = String(ip || '');
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(s)) return s.split('.').every((o) => Number(o) <= 255);
  return /^[0-9a-f:]+$/i.test(s) && s.includes(':') && s.length <= 39;
}

function neverBan(ip, extra = process.env.WATCHDOG_BAN_IGNORE) {
  const allow = new Set([...ALWAYS_ALLOW, ...String(extra || '').split(',').map((x) => x.trim()).filter(Boolean)]);
  if (allow.has(ip)) return true;
  return /^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(ip) || /^(fc|fd|fe80)/i.test(ip);
}

/** Count one probe; returns true when this IP has just crossed the threshold (now banned). */
function recordProbe(st, ip, now = Date.now()) {
  st.probes = st.probes || {};
  st.bans = st.bans || {};
  if (!isIp(ip) || neverBan(ip) || st.bans[ip]) return false;
  const list = (st.probes[ip] || []).filter((t) => now - t < WINDOW_MS);
  list.push(now);
  st.probes[ip] = list;
  if (list.length < THRESHOLD) return false;
  st.bans[ip] = { at: now, until: now + BAN_MS, probes: list.length };
  delete st.probes[ip];
  return true;
}

/** Drop expired bans and stale probe counts; returns true when the ban list changed. */
function prune(st, now = Date.now()) {
  st.probes = st.probes || {};
  st.bans = st.bans || {};
  let changed = false;
  for (const [ip, b] of Object.entries(st.bans)) if (!(b.until > now)) { delete st.bans[ip]; changed = true; }
  for (const [ip, list] of Object.entries(st.probes)) {
    const keep = list.filter((t) => now - t < WINDOW_MS);
    if (keep.length) st.probes[ip] = keep; else delete st.probes[ip];
  }
  return changed;
}

/** The nginx deny file for the current bans (only valid IPs — it is nginx config). */
function renderDenyFile(st) {
  const ips = Object.keys(st.bans || {}).filter(isIp).sort();
  return [
    '# Managed by apps/backend/scripts/watchdog/scannerBan.js — secret-file scanners,',
    '# banned for 7 days after 5 probes in 10 minutes. Do not edit by hand.',
    ...ips.map((ip) => `deny ${ip};`),
    '',
  ].join('\n');
}

/** Write the deny file and reload nginx; restores the previous file if the config test fails. */
function applyDenyFile(content) {
  const run = (args, input) => execFileSync('sudo', ['-n', ...args], { timeout: 20000, input });
  let previous = null;
  try { previous = run(['cat', DENY_FILE]).toString(); } catch (_) { /* first write */ }
  run(['tee', DENY_FILE], content);
  try {
    run(['nginx', '-t']);
  } catch (e) {
    if (previous != null) run(['tee', DENY_FILE], previous);
    throw new Error(`nginx -t failed with the new deny list; previous list restored (${String(e.message).slice(0, 120)})`);
  }
  run(['systemctl', 'reload', 'nginx']);
}

module.exports = { DENY_FILE, WINDOW_MS, THRESHOLD, BAN_MS, isIp, neverBan, recordProbe, prune, renderDenyFile, applyDenyFile };
