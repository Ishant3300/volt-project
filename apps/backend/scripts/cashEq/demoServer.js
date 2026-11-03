'use strict';

// Local demo of the equity backend for web-portal work — NOT for the server.
//
//   node scripts/cashEq/demoServer.js        → http://localhost:3000 (web .env.local points here)
//
// Runs the REAL equity code (src/cashEq routes, rules, orders, low-volume fills, engine,
// month-end) on the in-memory store used by the tests (tests/helpers/cashEqFakeDb.js),
// with simulated NSE prices (5-level depth, growing volume) instead of Kite. No MongoDB,
// no Redis, no Kite, nothing live. Data is lost when it stops.
//
// Demo sign-ins (local test values only): see DEMO_ACCOUNTS below.

const Module = require('module');
const path = require('path');
const http = require('http');
const express = require('express');
const jwt = require('jsonwebtoken');
const { WebSocketServer } = require('ws');

process.env.JWT_SECRET = process.env.JWT_SECRET || 'cash-eq-local-demo-only';
const SRC = path.join(__dirname, '..', '..', 'src');
const resolve = (p) => require.resolve(path.join(SRC, p));
const stub = (p, exports) => {
  const file = resolve(p);
  require.cache[file] = Object.assign(new Module(file), { id: file, filename: file, loaded: true, exports });
};

// --- Stand-ins for everything outside src/cashEq -------------------------------------
const DEMO_ADMIN = { _id: '64b0000000000000000000a1', username: 'admin', name: 'Demo Admin', password: 'demo1234' };
stub('services/redisService.js', { getClient: () => ({ get: async (k) => (k === 'cashEq:enabled' ? '1' : null) }), isAvailable: () => true });
stub('models/Admin.js', {
  exists: async (q) => (q.username === DEMO_ADMIN.username ? { _id: DEMO_ADMIN._id } : null),
  findById: (id) => {
    const v = String(id) === DEMO_ADMIN._id ? { _id: DEMO_ADMIN._id, username: DEMO_ADMIN.username, watch_only: false } : null;
    return { select: () => ({ lean: async () => v }), lean: async () => v };
  },
});
stub('models/Master.js', { exists: async () => null });
stub('models/User.js', { exists: async () => null });
stub('services/kiteService.js', { getStoredAccessToken: async () => null });
stub('cashEq/txn.js', { withTxn: (fn) => fn(null) });
const actualModels = require(resolve('cashEq/models.js'));
const { makeFake } = require(path.join(__dirname, '..', '..', 'tests', 'helpers', 'cashEqFakeDb'));
const models = Object.fromEntries(Object.entries(actualModels).map(([k, v]) => [k, makeFake(v)]));
stub('cashEq/models.js', models);
const engine = require(resolve('cashEq/engine.js'));
engine.marketOpen = () => true; // demo: market always open
const feed = require(resolve('cashEq/feed.js'));
feed.refresh = async () => {}; // no Kite
const orders = require(resolve('cashEq/orders.js'));
const cashAuth = require(resolve('cashEq/auth.js'));

// --- Demo data ------------------------------------------------------------------------
const STOCKS = [
  // token, symbol, name, price, approved, daily volume scale (thin stocks trade little)
  [738561, 'RELIANCE', 'RELIANCE INDUSTRIES', 1412.6, true, 400000],
  [408065, 'INFY', 'INFOSYS', 1488.05, true, 300000],
  [341249, 'HDFCBANK', 'HDFC BANK', 1742.3, true, 350000],
  [779521, 'SBIN', 'STATE BANK OF INDIA', 812.35, true, 500000],
  [2953217, 'TCS', 'TATA CONSULTANCY SERV', 3050.4, true, 120000],
  [3001089, 'KPIGREEN', 'KPI GREEN ENERGY', 352.4, true, 60000],
  [4632577, 'SMALLCO', 'SMALL CO (DEMO, THIN)', 48.75, false, 800],
  [5197313, 'TINYCAP', 'TINY CAP (DEMO, ILLIQUID)', 12.4, false, 50],
];
const DEMO_ACCOUNTS = { password: 'demo1234' }; // every demo equity account uses this (local only)

async function seed() {
  const bcrypt = require('bcryptjs');
  const pw = await bcrypt.hash(DEMO_ACCOUNTS.password, 4);
  for (const [token, sym, name, , mtf] of STOCKS) {
    await models.EqInstrument.create({ instrument_token: token, tradingsymbol: sym, name, tick_size: 0.05, mtf, is_active: true });
  }
  const pct = (intraday, carry) => ({ mode: 'PCT', intraday, carry, min_rate: 0, higher_side_only: false });
  const top = await models.EqMaster.create({
    name: 'Equity Top', username: 'EQTOP01', password: pw, per_script_limit: 2500000, total_limit: 20000000,
    brokerage_mtf: pct(0.02, 0.1), brokerage_non: pct(0.03, 0.2), interest_mtf_pct: 12, interest_non_pct: 15,
    pnl_share: 60, brokerage_share: 50, interest_share: 50,
  });
  const sub = await models.EqMaster.create({
    name: 'Equity Sub', username: 'EQSUB01', password: pw, parent_id: top._id, per_script_limit: 2000000, total_limit: 10000000,
    brokerage_mtf: pct(0.03, 0.15), brokerage_non: pct(0.05, 0.3), interest_mtf_pct: 15, interest_non_pct: 18,
    pnl_share: 30, brokerage_share: 40, interest_share: 40,
  });
  for (const [username, name, opening, master] of [['EQC0001', 'Ramesh K', 1000000, sub], ['EQC0002', 'Suresh P', 500000, sub], ['EQC0003', 'Meena S', 200000, top]]) {
    await models.EqClient.create({
      name, username, password: pw, master_id: master._id, per_script_limit: 2000000, total_limit: 10000000,
      opening_balance: opening, opening_type: 'Cr',
      brokerage_mtf: pct(0.03, 0.2), brokerage_non: pct(0.05, 0.4), interest_mtf_pct: 18, interest_non_pct: 21,
    });
  }
}

// --- Simulated NSE prices -------------------------------------------------------------
const state = new Map();
function tick() {
  const nowSec = Math.floor(Date.now() / 1000);
  const ticks = [];
  for (const [token, , , base, , scale] of STOCKS) {
    const s = state.get(token) || { ltp: base, close: base, open: base, high: base, low: base, volume: Math.round(scale * 0.3), lastTrade: nowSec };
    const traded = Math.random() < (scale < 100 ? 0.05 : 0.9); // illiquid stocks rarely trade
    if (traded) {
      s.ltp = Math.max(0.05, Math.round((s.ltp * (1 + (Math.random() - 0.5) * 0.002)) * 20) / 20);
      s.volume += Math.max(1, Math.round(scale * Math.random() * 0.002));
      s.lastTrade = nowSec;
      s.high = Math.max(s.high, s.ltp);
      s.low = Math.min(s.low, s.ltp);
    }
    state.set(token, s);
    const spread = scale < 1000 ? 0.4 : 0.05;
    const lvl = (side, i) => {
      const price = Math.round((side === 'buy' ? s.ltp - spread * (i + 1) : s.ltp + spread * (i + 1)) * 20) / 20;
      return { price, qty: Math.max(1, Math.round((scale / 50) * (1 + i) * (0.5 + Math.random()))), orders: 1 + i };
    };
    const depth = { buy: [0, 1, 2, 3, 4].map((i) => lvl('buy', i)), sell: [0, 1, 2, 3, 4].map((i) => lvl('sell', i)) };
    ticks.push({
      instrument_token: token, last_price: s.ltp, volume: s.volume, open: s.open, high: s.high, low: s.low, close: s.close,
      change: Math.round((s.ltp - s.close) * 100) / 100, change_percent: Math.round(((s.ltp - s.close) / s.close) * 10000) / 100,
      last_trade_ts: s.lastTrade, depth, bid_price: depth.buy[0].price, ask_price: depth.sell[0].price,
    });
  }
  feed._onTicks(ticks); // quotes + the equity order matcher, exactly as the real feed does
}

// --- HTTP + WebSocket -------------------------------------------------------------------
const app = express();
app.use((req, res, next) => {
  res.set('Access-Control-Allow-Origin', req.headers.origin || '*');
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  return next();
});
app.use(express.json());

app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body || {};
  if (username === DEMO_ADMIN.username && password === DEMO_ADMIN.password) {
    const token = jwt.sign({ id: DEMO_ADMIN._id, role: 'admin', investor: false }, process.env.JWT_SECRET);
    return res.json({ success: true, message: 'Login successful', data: { token, role: 'ADMIN', admin: { id: DEMO_ADMIN._id, username: 'admin', name: DEMO_ADMIN.name, is_super_admin: true, permissions: [] } } });
  }
  const r = await cashAuth.tryLogin(username, password, req);
  if (r) return res.status(r.status).json(r.body);
  return res.status(401).json({ success: false, message: 'Invalid credentials', data: null });
});
app.use('/api/cash-eq', require(resolve('cashEq/routes.js')));
// The F&O screens of an admin session: answer empty so the shell loads (demo only).
app.use('/api', (req, res) => res.json({ success: true, message: 'demo', data: [] }));

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws/live-prices' });
const sockets = new Map(); // userId -> Set(ws)
wss.on('connection', (ws) => {
  ws.send(JSON.stringify({ type: 'connected', kiteConnected: true }));
  ws.on('message', (raw) => {
    try {
      const m = JSON.parse(String(raw));
      if (m.type === 'auth') {
        const d = jwt.verify(m.token, process.env.JWT_SECRET);
        if (!sockets.has(String(d.id))) sockets.set(String(d.id), new Set());
        sockets.get(String(d.id)).add(ws);
        ws.userId = String(d.id);
        ws.send(JSON.stringify({ type: 'auth_ok', userId: ws.userId }));
      }
    } catch (_) { /* ignore */ }
  });
  ws.on('close', () => sockets.get(ws.userId)?.delete(ws));
});
const lps = {
  broadcastToUser(userId, data) {
    for (const ws of sockets.get(String(userId)) || []) if (ws.readyState === 1) ws.send(JSON.stringify(data));
  },
};

seed().then(() => {
  feed.lps = lps;
  feed.addListener(orders.onTicks);
  tick();
  setInterval(tick, 1000);
  setInterval(() => feed.push(), 1000);
  server.listen(3000, () => console.log('Equity demo backend on http://localhost:3000 (in-memory, simulated prices; demo password in DEMO_ACCOUNTS)'));
});
