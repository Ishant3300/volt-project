'use strict';

const { clientIp, recordLoginFailure } = require('../utils/eventLog');

/**
 * Records every FAILED sign-in on a login route (LoginAttempt) by watching the
 * response the route sends — so none of the login handlers' many refusal
 * paths has to be touched. Mounted before validateLogin so an empty form is
 * seen too. Success is already in LoginHistory. The password is never read.
 */
function trackLoginAttempt(route) {
  return function trackLoginAttemptMiddleware(req, res, next) {
    const originalJson = res.json.bind(res);
    res.json = (body) => {
      try {
        if (res.statusCode >= 400) {
          recordLoginFailure({
            route,
            username: req.body && typeof req.body.username === 'string' ? req.body.username : '',
            status: res.statusCode,
            reason: body && typeof body.message === 'string' ? body.message : '',
            ip: clientIp(req),
            userAgent: req.headers['user-agent'],
          });
        }
      } catch (_) { /* never affects the login */ }
      return originalJson(body);
    };
    next();
  };
}

module.exports = { trackLoginAttempt };
