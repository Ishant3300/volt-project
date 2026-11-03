'use strict';

// Equity sign-in and route guard.
//
// Equity masters / clients get tokens with their own roles ('cash_master' / 'cash_client').
// Every F&O route accepts only 'user' / 'master' / 'admin' (middlewares/auth.js), so these
// tokens are refused there automatically; F&O 'user' / 'master' tokens are refused here.
// Admins use their normal admin token on both.
//
// The guard keeps the signed-in account on req.cash — never req.admin / req.master — so the
// F&O action log (middlewares/auditActions.js) doesn't record equity actions; equity has
// its own log (eqcash_audit).

const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const Admin = require('../models/Admin');
const { EqMaster, EqClient } = require('./models');
const { enabled, appAllowed } = require('./switch');

const ROLE_MODEL = { cash_master: EqMaster, cash_client: EqClient };

const deny = (res, status, message, extra) => res.status(status).json({ success: false, message, data: extra || null });

// `sid` makes every sign-in's token unique (two sign-ins in the same second would otherwise
// get the same token, and the newer one wouldn't end the older session).
const generateToken = (id, role) => jwt.sign(
  { id, role, investor: false, sid: crypto.randomBytes(8).toString('hex') },
  process.env.JWT_SECRET,
  { expiresIn: '30d' }
);

/**
 * Sign-in for an equity account, called by the universal login only after no admin,
 * master or client matched. Returns { status, body } to send, or null (not an equity
 * account, or equity is switched off) so the login answers "Invalid credentials" as before.
 */
async function tryLogin(username, password, req) {
  if (typeof username !== 'string' || !/^EQ/i.test(username.trim())) return null;
  if (!(await enabled())) return null;
  const name = username.trim().toUpperCase();
  for (const [role, Model] of Object.entries(ROLE_MODEL)) {
    const acc = await Model.findOne({ username: name });
    if (!acc || acc.deleted_at || !(await bcrypt.compare(password, acc.password))) continue;
    if (acc.status !== 'active') return { status: 403, body: { success: false, message: 'Account is not active', data: null } };
    if (!(await appAllowed(req))) {
      return {
        status: 403,
        body: { success: false, message: 'Equity accounts sign in on the web portal for now. The app will support them soon.', data: null },
      };
    }
    const token = generateToken(acc._id, role);
    acc.active_token = token;
    acc.last_login = new Date();
    acc.ip_address = req.ip || null;
    await acc.save();
    return {
      status: 200,
      body: {
        success: true,
        message: acc.change_pass_on_first_login ? 'Password change required' : 'Login successful',
        data: {
          token,
          [role]: acc.toJSON(),
          role: role.toUpperCase(),
          requires_password_change: !!acc.change_pass_on_first_login,
          investor: false,
        },
      },
    };
  }
  return null;
}

/**
 * Route guard: `roles` from 'admin' | 'cash_master' | 'cash_client'. Sets req.cash =
 * { role, id, username, doc }. Also refuses everything while equity is switched off.
 */
function requireCash(...roles) {
  return async (req, res, next) => {
    try {
      if (!(await enabled())) return deny(res, 404, 'Not found');
      const token = req.headers.authorization?.split(' ')[1];
      if (!token) return deny(res, 401, 'Authentication token required');
      let decoded;
      try {
        decoded = jwt.verify(token, process.env.JWT_SECRET);
      } catch (_) {
        return deny(res, 401, 'Invalid or expired token');
      }
      if (!roles.includes(decoded.role)) return deny(res, 403, 'Equity is not available for this account');

      if (decoded.role === 'admin') {
        const admin = await Admin.findById(decoded.id).select('username deleted_at active_status watch_only').lean();
        if (!admin || admin.deleted_at || admin.active_status === false) return deny(res, 401, 'Admin not found');
        req.cash = { role: 'admin', id: String(admin._id), username: admin.username, watchOnly: !!admin.watch_only, doc: admin };
        return next();
      }

      const Model = ROLE_MODEL[decoded.role];
      const acc = await Model.findById(decoded.id);
      if (!acc || acc.deleted_at) return deny(res, 401, 'Account not found');
      // Clients: one session at a time (like F&O clients). Masters: several devices.
      if (decoded.role === 'cash_client' && acc.active_token !== token) return deny(res, 401, 'Session expired. Please login again');
      if (acc.status !== 'active') return deny(res, 403, 'Account is not active');
      const path = req.originalUrl.split('?')[0];
      if (acc.change_pass_on_first_login && !/\/api\/cash-eq\/me(\/password)?\/?$/.test(path)) {
        return deny(res, 403, 'Password change required before accessing the application', { requires_password_change: true });
      }
      req.cash = { role: decoded.role, id: String(acc._id), username: acc.username, watchOnly: false, doc: acc };
      return next();
    } catch (err) {
      return deny(res, 500, 'Something went wrong');
    }
  };
}

/** Refuse changes from watch-only admins. */
function noWatchOnly(req, res, next) {
  if (req.cash?.watchOnly) return deny(res, 403, 'Watch-only admins cannot make changes');
  return next();
}

module.exports = { tryLogin, requireCash, noWatchOnly, generateToken };
