'use strict';

/**
 * Pure helpers for the watchdog (no I/O) — log-line classification, error
 * signatures, alert cooldowns, IST market windows, Telegram text escaping.
 * Unit-tested in tests/watchdogLib.unit.test.js.
 */

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

/** { day: 0=Sun..6=Sat, minutes: minutes since IST midnight, ymd } for a time. */
function istParts(now = Date.now()) {
  const d = new Date(now + IST_OFFSET_MS);
  return { day: d.getUTCDay(), minutes: d.getUTCHours() * 60 + d.getUTCMinutes(), ymd: d.toISOString().slice(0, 10), hhmm: d.toISOString().slice(11, 16) };
}

const isWeekday = (p) => p.day >= 1 && p.day <= 5;
/** NSE cash/F&O 09:15-15:30, MCX 09:00-23:30 (Mon-Fri, holidays not known here). */
function inMarketHours(now = Date.now()) {
  const p = istParts(now);
  return { nse: isWeekday(p) && p.minutes >= 555 && p.minutes < 930, mcx: isWeekday(p) && p.minutes >= 540 && p.minutes < 1410 };
}
/** NSE IX (GIFT NIFTY) sessions 06:30-15:40 and 16:35-02:45 IST. */
function inGiftSession(now = Date.now()) {
  const m = istParts(now).minutes;
  return (m >= 390 && m < 940) || m >= 995 || m < 165;
}

/** Groups messages that differ only in ids, numbers, quotes or paths. */
function signature(message) {
  return String(message || '')
    .replace(/[0-9a-f]{24}/gi, '<id>')
    .replace(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, '<token>')
    .replace(/https?:\/\/\S+/g, '<url>')
    .replace(/"[^"]{0,120}"|'[^']{0,120}'/g, '<s>')
    .replace(/\b\d+(\.\d+)?\b/g, 'N')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 160);
}

// Known, harmless lines (also excluded by dailyHealthAudit.sh).
const NOISE = [
  /\[MONGOOSE\] Warning/, /trace-warnings/, /ALLOWED_ORIGINS/, /MarketCalendar/, /GiftNiftyFeed/, /MassiveFeed/,
  /ExpiryActions\].*not planned yet/, /^\s*at /, /node_modules/,
];

const RULES = [
  { re: /MongoNetworkError|MongoServerSelectionError|PoolClearedError|ECONNREFUSED.*27017|Topology is closed|topology was destroyed/i, severity: 'critical', key: 'db-error', title: 'Database connection error' },
  { re: /uncaughtException|Unhandled(Promise)?Rejection|unhandled rejection/i, severity: 'warning', key: 'unhandled', title: 'Unhandled error in the backend' },
  { re: /Kite WebSocket (closed|error|disconnected)|Kite.*\b403\b|auto-?login.*fail|Kite.*(token|session).*(expired|invalid)/i, severity: 'warning', key: 'kite-feed', title: 'Kite price feed problem' },
  { re: /STALE TICK SKIPPED/, severity: 'warning', key: 'stale-tick', title: 'Stale ticks skipped for order matching' },
  { re: /orphan/i, severity: 'warning', key: 'orphan', title: 'Order-book orphan found/healed' },
  { re: /JavaScript heap out of memory|FATAL ERROR/i, severity: 'critical', key: 'fatal', title: 'Backend fatal error' },
];

/**
 * A new pm2 log line -> { severity, key, title, line } or null.
 * `isErrLog`: from the error log, where any other Error/❌ line is reported as
 * a generic error grouped by its signature.
 */
function classifyLogLine(line, isErrLog) {
  // pm2 writes "<timestamp>: <text>" — strip exactly that, keeping the text's
  // own indentation (continuation lines of a dump are indented).
  const text = String(line || '').replace(/^\d{4}-\d{2}-\d{2}T[\d:.]+Z?: ?/, '');
  if (!text.trim()) return null;
  for (const r of RULES) if (r.re.test(text)) return { severity: r.severity, key: r.key, title: r.title, line: text.slice(0, 300) };
  if (NOISE.some((n) => n.test(text))) return null;
  // Continuation of a multi-line dump (object properties, stack frames,
  // braces) — only an error's first line counts.
  if (/^\s/.test(text) || /^[}\])]/.test(text) || /^\{\s*$/.test(text) || /^['"]?[\w$]+['"]?:\s.*[,{[]\s*$/.test(text)) return null;
  if (isErrLog && /Error|❌/.test(text)) {
    return { severity: 'warning', key: `err:${signature(text)}`, title: 'Backend error', line: text.slice(0, 300), generic: true };
  }
  return null;
}

/** One nginx access-log line -> { ip, time, method, path, status } or null. */
function parseNginxLine(line) {
  const m = /^(\S+) \S+ \S+ \[([^\]]+)\] "(\S+) (\S+)[^"]*" (\d{3})/.exec(line);
  if (!m) return null;
  return { ip: m[1], time: m[2], method: m[3], path: m[4], status: Number(m[5]) };
}

const SENSITIVE_PATH = /\.env\b|\.git\/|\.aws\/|credentials|wp-config|\.sql\b|\.bak\b|id_rsa|\.pem\b/i;

/**
 * Cooldown gate. state.sent: key -> last sent epoch ms. critical repeats every
 * 5 min while active; warning every `cooldownMs` (default 15 min); info hourly.
 */
function shouldSend(sent, key, severity, now = Date.now(), cooldownMs) {
  const every = cooldownMs ?? (severity === 'critical' ? 5 * 60_000 : severity === 'warning' ? 15 * 60_000 : 60 * 60_000);
  const last = sent[key];
  if (last != null && now - last < every) return false;
  sent[key] = now;
  return true;
}

function escapeHtml(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

const ICON = { critical: '🔴', warning: '🟠', info: '🟢', resolved: '✅' };

/** Telegram HTML message: icon + bold title + body lines. */
function formatAlert(severity, title, lines = []) {
  const body = lines.filter(Boolean).map((l) => escapeHtml(l)).join('\n');
  return `${ICON[severity] || ''} <b>${escapeHtml(title)}</b>${body ? `\n${body}` : ''}`.slice(0, 3900);
}

/** Rule-based (client's own) refusal vs anything else. */
const RULE_REFUSAL = /wallet balance|Insufficient|breakup|exceeds|close-only|Fresh Stop-Loss|Price restriction|High-Low restriction|not allowed for this account|not permitted to trade|Trading is (currently disabled|blocked)|contract has expired|Only market orders|Cannot open new positions|cannot open new positions|deactivated this script|short position|would exceed your open position|Option selling|Blocked in app|GIFT NIFTY is not trading|limit price|Maximum allowed|allowed max/i;
const isRuleRefusal = (message) => RULE_REFUSAL.test(String(message || ''));

module.exports = {
  istParts, inMarketHours, inGiftSession, signature, classifyLogLine, parseNginxLine, SENSITIVE_PATH,
  shouldSend, escapeHtml, formatAlert, isRuleRefusal,
};
