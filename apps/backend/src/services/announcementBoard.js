/**
 * The app/web announcement banner as sections in ONE scrolling line.
 *
 * Before, the banner held a single message and every source replaced it:
 * the 08:00 NSE ban-list sync wiped an admin's notice and vice versa, and a
 * "NEW CONTRACT Open" notice was never shown unless someone published it by
 * hand (CRUDE 19 NOV opened 15 Oct 2026 with no notice). Now each source
 * owns its section:
 *   manual  — an admin's own message (Admin → Announcement)
 *   expiry  — one per open day, posted automatically when contracts open,
 *             shown until the old contract's settlement time
 *   corp    — one per corporate-action cut (split / bonus / rights /
 *             dividend, corporateActionCutService.js) until it runs
 *   ban     — today's NSE F&O ban list (removed on a day with no bans)
 * GET /announcements/active joins the live sections into one line, so the
 * app and web (one-line marquee, mobile shows only the first line of text)
 * need no change.
 */
const Announcement = require('../models/Announcement');

const ORDER = ['manual', 'corp', 'expiry', 'ban'];
const SEPARATOR = '      |      ';

/** One line: the mobile banner shows only the first line of a message. */
function toLine(message) {
  const lines = String(message || '').split('\n').map((l) => l.trim()).filter(Boolean);
  let out = '';
  for (const l of lines) {
    if (!out) out = l;
    else if (/[-:]$/.test(out)) out += ` ${l}`; // "MCX -" + "CRUDEOIL"
    else out += ` · ${l}`;
  }
  return out.replace(/\s+/g, ' ').trim();
}

const sameSection = (source, ref) => (source === 'manual'
  ? { is_active: true, $or: [{ source: 'manual' }, { source: { $exists: false } }, { source: null }] }
  : { is_active: true, source, ...(ref ? { ref } : {}) });

/** Replace one section (same source, and same ref for expiry notices). */
async function postSection(source, message, { ref = null, expiresAt = null, createdBy } = {}) {
  const text = toLine(message);
  if (!text) throw Object.assign(new Error('Message is required'), { status: 400 });
  await Announcement.updateMany(sameSection(source, ref), { $set: { is_active: false } });
  return Announcement.create({ message: text, is_active: true, source, ref, expires_at: expiresAt, created_by: createdBy || undefined });
}

async function clearSection(source, ref) {
  return Announcement.updateMany(sameSection(source, ref), { $set: { is_active: false } });
}

/** The banner as clients see it: live sections in a fixed order, one line. */
async function activeBanner(now = new Date()) {
  const rows = await Announcement.find({ is_active: true, $or: [{ expires_at: null }, { expires_at: { $gt: now } }] }).sort({ createdAt: 1 }).lean();
  if (!rows.length) return null;
  const rank = (r) => ORDER.indexOf(r.source || 'manual');
  rows.sort((a, b) => rank(a) - rank(b) || String(a.ref || '').localeCompare(String(b.ref || '')));
  const latest = rows.reduce((m, r) => (r.createdAt > m.createdAt ? r : m), rows[0]);
  return { id: latest._id, message: rows.map((r) => toLine(r.message)).join(SEPARATOR), created_at: latest.createdAt };
}

module.exports = { postSection, clearSection, activeBanner, toLine, SEPARATOR };
