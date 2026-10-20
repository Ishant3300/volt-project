'use strict';

/**
 * Practice mode only (docs/practice-trading.md):
 * POST /api/auth/practice-signup
 *   { name, email, password, experience, markets: [...], tokens }
 *
 * Creates a practice client under the PRACTICE master: login ID = email,
 * every chosen market's wallet funded with `tokens` (practice money, no real
 * value), no brokerage (the practice database has no brokerage rules), no
 * quantity limits, no first-login password change. Answers exactly like a
 * login, so the app / web are signed straight in. Rate-limited per IP.
 */
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const User = require('../models/User');
const Master = require('../models/Master');

const MARKETS = {
  NSE_FUT: { exchange_name: 'NFO-FUT', turnover: true, lot: false, wallets: ['NSE', 'INDEX'] },
  NSE_OPT: { exchange_name: 'NFO-OPT', turnover: true, lot: false, wallets: ['NSEOPT'] },
  MCX: { exchange_name: 'MCX-FUT', turnover: false, lot: true, wallets: ['MCX'] },
  GLOBAL: { exchange_name: 'INDICES', turnover: true, lot: false, wallets: ['GLOBAL'] },
  COMEX: { exchange_name: 'COMEX-FUT', turnover: false, lot: true, wallets: ['COMEX'] },
};
const EXPERIENCE = ['new', 'under_1_year', '1_to_3_years', 'over_3_years'];
const MAX_TOKENS = 1e9;
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;

// Max 5 sign-ups per IP per hour (in memory — one practice process).
const hits = new Map();
function allow(ip) {
  const now = Date.now();
  const list = (hits.get(ip) || []).filter((t) => now - t < 3600e3);
  if (list.length >= 5) { hits.set(ip, list); return false; }
  list.push(now); hits.set(ip, list);
  if (hits.size > 10000) for (const [k, v] of hits) if (!v.some((t) => now - t < 3600e3)) hits.delete(k);
  return true;
}
const ipOf = (req) => String(req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '').split(',')[0].trim();
const bad = (res, message, code = 400) => res.status(code).json({ success: false, message, data: null });

const practiceSignup = async (req, res) => {
  try {
    const b = req.body || {};
    const name = String(b.name || '').trim();
    const email = String(b.email || '').trim().toLowerCase();
    const password = String(b.password || '');
    const experience = String(b.experience || '');
    const markets = Array.isArray(b.markets) ? [...new Set(b.markets.map(String))] : [];
    const tokens = Number(b.tokens);

    if (name.length < 2 || name.length > 60) return bad(res, 'Enter your name (2–60 characters).');
    if (!EMAIL.test(email) || email.length > 254) return bad(res, 'Enter a valid email address.');
    if (password.length < 6 || password.length > 100) return bad(res, 'Password must be at least 6 characters.');
    if (!EXPERIENCE.includes(experience)) return bad(res, 'Select your trading experience.');
    if (!markets.length || markets.some((m) => !MARKETS[m])) return bad(res, 'Select at least one market.');
    if (!Number.isFinite(tokens) || tokens < 1 || tokens > MAX_TOKENS) return bad(res, `Practice money must be between 1 and ${MAX_TOKENS.toLocaleString('en-IN')} tokens.`);
    if (!allow(ipOf(req))) return bad(res, 'Too many sign-ups from this network. Try again in an hour.', 429);

    if (await User.exists({ username: email })) return bad(res, 'An account with this email already exists. Log in instead.', 409);

    const master = await Master.findOne({ username: process.env.PRACTICE_MASTER_USERNAME || 'PRACTICE', deleted_at: null }).lean();
    if (!master) return bad(res, 'Practice sign-up is not available right now.', 503);

    const amount = Math.round(tokens * 100) / 100;
    const wallet = { NSE: 0, INDEX: 0, NSEOPT: 0, MCX: 0, COMEX: 0, GLOBAL: 0 };
    for (const m of markets) for (const w of MARKETS[m].wallets) wallet[w] = amount;

    const user = await User.create({
      name,
      profit_book_minutes: require('../utils/profitBookTime').DEFAULT_PROFIT_BOOK_MINUTES,
      username: email,
      password: await bcrypt.hash(password, 10),
      credits: amount,
      equity: amount,
      pnl_sharing: 0,
      brokerage_sharing: 0,
      exchanges_allowed: markets.map((m) => ({ exchange_name: MARKETS[m].exchange_name, turnover: MARKETS[m].turnover, lot: MARKETS[m].lot, group_name: 'PRACTICE' })),
      trade_limit: [],
      server_id: master.server_id,
      master_id: master._id,
      margin_square_off: false,
      change_pass_on_first_login: false,
      status: 'active',
      active_status: true,
      wallet,
    });
    await mongoose.connection.db.collection('practiceprofiles').insertOne({
      user_id: user._id, email, experience, markets, tokens: amount, ip: ipOf(req),
      user_agent: String(req.headers['user-agent'] || '').slice(0, 200), created_at: new Date(),
    });

    const token = jwt.sign({ id: user._id, role: 'user', investor: false }, process.env.JWT_SECRET, { expiresIn: '30d' });
    user.active_token = token;
    user.last_login = new Date();
    await user.save();
    return res.status(201).json({
      success: true,
      message: 'Practice account created',
      data: { token, user: user.toJSON(), role: 'USER', requires_password_change: false, investor: false, practice: true },
    });
  } catch (error) {
    if (error && error.code === 11000) return bad(res, 'An account with this email already exists. Log in instead.', 409);
    console.error('[practiceSignup]', error.message);
    return bad(res, 'Could not create the account. Try again.', 500);
  }
};

module.exports = { practiceSignup, MARKETS, EXPERIENCE };
