/**
 * Records every successful admin/master change (models/AdminAction.js) so
 * the health watchdog can say WHO changed a client's settings, moved money,
 * edited brokerage or placed / modified an order for a client.
 *
 * Mounted once on /api before the routers. The route's own auth middleware
 * sets req.admin / req.master later; they're read when the response
 * finishes. Never blocks or alters a request: recording happens after the
 * response is sent and any failure is only logged.
 */
const SKIP = [
  /^\/api\/auth\//, // logins, client events, internal health
  /^\/api\/trade\/metrics/, // read-only
  /^\/api\/trade\/app-rejection/, // app reports, not a change
  /\/messages(\/|$)/,
  /^\/api\/watchlist/,
  /^\/api\/kite\/quotes/,
  /\/totp\/(generate|verify-setup)/,
];
const SECRET = /pass|pin|token|secret|otp|totp|code|key/i;
const OBJECT_ID = /^[a-f0-9]{24}$/i;

function clean(v, depth = 0) {
  if (v == null || typeof v === 'number' || typeof v === 'boolean') return v;
  if (typeof v === 'string') return v.length > 200 ? `${v.slice(0, 200)}…` : v;
  if (depth >= 4) return '…';
  if (Array.isArray(v)) {
    const out = v.slice(0, 50).map((x) => clean(x, depth + 1));
    if (v.length > 50) out.push(`…${v.length - 50} more`);
    return out;
  }
  if (typeof v === 'object') {
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = SECRET.test(k) ? (x ? '[changed]' : x) : clean(x, depth + 1);
    return out;
  }
  return String(v);
}

function targetIds(path, body) {
  const ids = new Set(path.split('/').filter((s) => OBJECT_ID.test(s)));
  const pick = (o) => {
    if (!o || typeof o !== 'object') return;
    for (const k of ['user_id', 'userId', 'master_id', 'masterId', 'client_id', 'target_id', 'id']) {
      if (typeof o[k] === 'string' && OBJECT_ID.test(o[k])) ids.add(o[k]);
    }
    for (const k of ['user_ids', 'userIds', 'master_ids']) {
      if (Array.isArray(o[k])) for (const x of o[k].slice(0, 200)) if (typeof x === 'string' && OBJECT_ID.test(x)) ids.add(x);
    }
  };
  pick(body);
  return [...ids];
}

async function record(req, res, path, actor, result) {
  const AdminAction = require('../models/AdminAction');
  let username = null;
  try {
    const Model = actor.type === 'admin' ? require('../models/Admin') : require('../models/Master');
    username = (await Model.findById(actor.id).select('username').lean())?.username || null;
  } catch (_) { /* name is optional */ }
  let body = clean(req.body || null);
  if (body && JSON.stringify(body).length > 8000) body = { _truncated: true, keys: Object.keys(req.body || {}) };
  await AdminAction.create({
    actor_type: actor.type,
    actor_id: String(actor.id),
    actor_username: username,
    method: req.method,
    path,
    status_code: res.statusCode,
    target_ids: targetIds(path, req.body),
    body,
    result,
    ip: req.ip || null,
  });
}

module.exports = function auditActions(req, res, next) {
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) return next();
  const path = (req.originalUrl || '').split('?')[0];
  if (SKIP.some((re) => re.test(path))) return next();

  // Keep the created/changed record's id and status from the response.
  let result = null;
  const json = res.json.bind(res);
  res.json = (payload) => {
    try {
      const data = payload && payload.data;
      const doc = data && (data.trade || data.user || data.master || data);
      if (doc && typeof doc === 'object' && !Array.isArray(doc)) {
        const id = doc._id || doc.id;
        result = { id: id ? String(id) : null, status: doc.status || null };
      }
    } catch (_) { /* ignore */ }
    return json(payload);
  };

  res.on('finish', () => {
    const actor = req.admin ? { type: 'admin', id: req.admin.id } : req.master ? { type: 'master', id: req.master.id } : null;
    if (!actor || !actor.id || res.statusCode >= 400) return;
    record(req, res, path, actor, result).catch((e) => console.error('[auditActions] not recorded:', e.message));
  });
  next();
};

module.exports._test = { clean, targetIds };
