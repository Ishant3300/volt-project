const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const ClientEvent = require('../models/ClientEvent');
const { clientIp, cleanText } = require('../utils/eventLog');

/**
 * POST /api/auth/client-events  { events: [{ source, kind, code, message, page, context, version, target_user_id }] }
 *
 * The web portal / app report problems the server would never see otherwise
 * (an order refused on screen, a crash, a failed request). Works signed out
 * too (login page). The account comes from the bearer token when one is
 * valid, never from the body. Up to 20 events per call and 60 per minute per
 * account/IP; extra ones are dropped. Always answers 200 for a well-formed
 * call — the caller fires and forgets.
 */

const SOURCES = ['web', 'app'];
const KINDS = ['order_block', 'order_rejected', 'js_error', 'api_error', 'crash'];
const MAX_PER_CALL = 20;
const MAX_PER_MINUTE = 60;
const buckets = new Map(); // key -> { windowStart, count }

function allow(key, n) {
  const now = Date.now();
  const b = buckets.get(key);
  if (!b || now - b.windowStart > 60_000) {
    buckets.set(key, { windowStart: now, count: n });
    if (buckets.size > 5000) for (const [k, v] of buckets) if (now - v.windowStart > 60_000) buckets.delete(k);
    return n;
  }
  const room = Math.max(0, MAX_PER_MINUTE - b.count);
  b.count += Math.min(n, room);
  return Math.min(n, room);
}

function caller(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return { id: null, role: null };
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    return { id: mongoose.Types.ObjectId.isValid(String(decoded.id)) ? decoded.id : null, role: cleanText(decoded.role, 20) || null };
  } catch (_) {
    return { id: null, role: null };
  }
}

/** Plain JSON object of short scalar values only (max 15 keys). */
function cleanContext(ctx) {
  if (!ctx || typeof ctx !== 'object' || Array.isArray(ctx)) return {};
  const out = {};
  for (const [k, v] of Object.entries(ctx).slice(0, 15)) {
    const key = cleanText(k, 40).replace(/[.$]/g, '_');
    if (!key) continue;
    if (typeof v === 'number' || typeof v === 'boolean') out[key] = v;
    else if (typeof v === 'string') out[key] = cleanText(v, 200);
  }
  return out;
}

const recordClientEvents = async (req, res) => {
  try {
    const list = Array.isArray(req.body && req.body.events) ? req.body.events.slice(0, MAX_PER_CALL) : null;
    if (!list) return res.status(400).json({ success: false, message: 'events must be a list', data: null });
    const who = caller(req);
    const ip = clientIp(req);
    const allowed = allow(who.id ? `a:${who.id}` : `ip:${ip}`, list.length);
    const docs = [];
    for (const e of list.slice(0, allowed)) {
      if (!e || !SOURCES.includes(e.source) || !KINDS.includes(e.kind)) continue;
      docs.push({
        source: e.source,
        kind: e.kind,
        account_id: who.id,
        account_role: who.role,
        target_user_id: mongoose.Types.ObjectId.isValid(String(e.target_user_id || '')) ? e.target_user_id : null,
        code: cleanText(e.code, 40),
        message: cleanText(e.message),
        page: cleanText(e.page, 120),
        context: cleanContext(e.context),
        version: cleanText(e.version, 40),
        user_agent: cleanText(req.headers['user-agent'], 200),
        ip,
      });
    }
    if (docs.length) await ClientEvent.insertMany(docs, { ordered: false });
    res.status(200).json({ success: true, data: { stored: docs.length } });
  } catch (_) {
    res.status(200).json({ success: true, data: { stored: 0 } });
  }
};

module.exports = { recordClientEvents, _test: { cleanContext, allow, buckets } };
