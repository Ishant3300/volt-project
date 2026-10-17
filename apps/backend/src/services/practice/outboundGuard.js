'use strict';

/**
 * Practice mode catch-all (docs/practice-trading.md): every outbound axios
 * request to anything other than this machine is refused before it leaves.
 * Belt and braces on top of the per-service gates — even a path that was
 * missed can never reach Kite, NSE, MCX, NSE IX or Massive from practice.
 * (All backend HTTP clients use the default axios instance; Firebase push
 * uses Google's own client and is unaffected.)
 */
const axios = require('axios');

const ALLOWED_HOSTS = new Set(['localhost', '127.0.0.1', '::1']);

function hostOf(config) {
  try {
    const url = new URL(config.url, config.baseURL || 'http://localhost');
    return url.hostname;
  } catch (_) {
    return '';
  }
}

function install() {
  axios.interceptors.request.use((config) => {
    const host = hostOf(config);
    if (!ALLOWED_HOSTS.has(host)) {
      const err = new Error(`practice mode: outbound request to ${host || 'unknown host'} blocked`);
      err.code = 'PRACTICE_OUTBOUND_BLOCKED';
      throw err;
    }
    return config;
  });
  console.log('🛡️  [practice] outbound requests blocked (only localhost allowed)');
}

module.exports = { install, hostOf, ALLOWED_HOSTS };
