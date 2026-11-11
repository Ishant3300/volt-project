'use strict';

// Broker view: sign-in and route guard (owner, 11 Nov 2026).
//
// A broker token has its own role ('broker'). Every F&O route accepts only
// 'user' / 'master' / 'admin' (middlewares/auth.js), equity routes only their
// own roles — so a broker token is refused everywhere except /api/broker,
// which is read-only. The guard keeps the broker on req.broker (never
// req.admin / req.master / req.user).

const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const Broker = require('../models/Broker');

const ROLE = 'broker';
const deny = (res, status, message) => res.status(status).json({ success: false, message, data: null });

function generateToken(broker) {
  const since = broker.session_since ? new Date(broker.session_since).getTime() : 0;
  return jwt.sign(
    { id: String(broker._id), role: ROLE, investor: false, ss: since, sid: crypto.randomBytes(8).toString('hex') },
    process.env.JWT_SECRET,
    { expiresIn: '30d' },
  );
}

/** Public shape of a broker session (never the password). */
function brokerProfile(b) {
  return { id: String(b._id), _id: String(b._id), name: b.name, username: b.username, role: ROLE };
}

/**
 * Called by the universal login (authController.login) only after no admin,
 * master, client or equity account matched. Returns { status, body } to send,
 * or null (not a broker login) so the login answers "Invalid credentials".
 */
async function tryLogin(username, password, req) {
  if (typeof username !== 'string' || typeof password !== 'string') return null;
  const name = username.trim();
  if (!name) return null;
  const broker = await Broker.findOne({ username: name, deleted_at: null }).select('+password');
  if (!broker || !broker.password || !(await bcrypt.compare(password, broker.password))) return null;
  if (!broker.login_enabled || broker.status !== 'active') {
    return { status: 403, body: { success: false, message: 'You are not allowed to login', data: null } };
  }
  const token = generateToken(broker);
  broker.last_login = new Date();
  broker.ip_address = (req.headers['x-forwarded-for'] || req.ip || '').toString().split(',')[0].trim() || null;
  await broker.save();
  console.log(`🔐 [LOGIN] Broker ${broker.username} (${broker.name}) signed in`);
  return {
    status: 200,
    body: {
      success: true,
      message: 'Login successful',
      data: { token, broker: brokerProfile(broker), role: 'BROKER', requires_password_change: false, investor: false },
    },
  };
}

/** Route guard for /api/broker — sets req.broker = { id, name, username }. */
async function requireBroker(req, res, next) {
  try {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) return deny(res, 401, 'Authentication token required');
    let decoded;
    try {
      decoded = jwt.verify(token, process.env.JWT_SECRET);
    } catch (_) {
      return deny(res, 401, 'Invalid or expired token');
    }
    if (decoded.role !== ROLE) return deny(res, 403, 'Access denied');
    const broker = await Broker.findById(decoded.id).lean();
    if (!broker || broker.deleted_at) return deny(res, 401, 'Account not found');
    if (!broker.login_enabled || broker.status !== 'active') return deny(res, 403, 'You are not allowed to login');
    const since = broker.session_since ? new Date(broker.session_since).getTime() : 0;
    if (Number(decoded.ss || 0) !== since) return deny(res, 401, 'Session expired. Please login again');
    req.broker = { id: String(broker._id), name: broker.name, username: broker.username };
    return next();
  } catch (_) {
    return deny(res, 500, 'Something went wrong');
  }
}

/** The broker view is read-only: anything but GET is refused. */
function readOnly(req, res, next) {
  if (req.method !== 'GET') return deny(res, 405, 'The broker view is read-only');
  return next();
}

module.exports = { tryLogin, requireBroker, readOnly, brokerProfile, ROLE };
