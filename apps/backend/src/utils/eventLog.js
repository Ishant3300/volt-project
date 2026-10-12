'use strict';

/**
 * Fire-and-forget writers for the monitoring logs (LoginAttempt, ServerEvent)
 * and the shared request helpers they need. Never throw and never delay the
 * response they're recording — a logging failure must not affect a login or
 * an order.
 */

const MAX_TEXT = 300;

function clientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  let ip = forwarded
    ? String(forwarded).split(',')[0].trim()
    : req.ip || req.socket?.remoteAddress || '';
  if (ip && ip.startsWith('::ffff:')) ip = ip.slice(7);
  return ip || '';
}

/** Control characters removed, whitespace collapsed, length capped. */
function cleanText(value, max = MAX_TEXT) {
  if (value == null) return '';
  return String(value).replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}

function recordLoginFailure({ route, username, status, reason, ip, userAgent }) {
  setImmediate(() => {
    try {
      const LoginAttempt = require('../models/LoginAttempt');
      LoginAttempt.create({
        route: cleanText(route, 20),
        username: cleanText(username, 60),
        status: Number(status) || 0,
        reason: cleanText(reason, 200),
        ip: cleanText(ip, 60),
        user_agent: cleanText(userAgent, 200),
      }).catch(() => {});
    } catch (_) { /* never affects the login */ }
  });
}

function recordServerEvent({ kind, userId, callerRole, status, message, context }) {
  setImmediate(() => {
    try {
      const ServerEvent = require('../models/ServerEvent');
      ServerEvent.create({
        kind: cleanText(kind, 40),
        user_id: userId || null,
        caller_role: cleanText(callerRole, 20),
        status: Number(status) || 0,
        message: cleanText(message),
        context: context || {},
      }).catch(() => {});
    } catch (_) { /* never affects the request */ }
  });
}

module.exports = { clientIp, cleanText, recordLoginFailure, recordServerEvent };
