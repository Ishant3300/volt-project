// Equity M3: NSE EQ stock list, approved (MTF) list, the separate Kite feed (against a
// local fake Kite server), watchlist/prices routes, and code-level separation from F&O.

process.env.JWT_SECRET = 'cash-eq-test-secret';

const redisStore = {};
jest.mock('../src/services/redisService', () => ({
  getClient: () => ({ get: async (k) => (k in redisStore ? redisStore[k] : null) }),
  isAvailable: () => true,
}));
jest.mock('../src/cashEq/models', () => {
  const actual = jest.requireActual('../src/cashEq/models');
  const { makeFake } = require('./helpers/cashEqFakeDb');
  const out = {};
  for (const [k, v] of Object.entries(actual)) out[k] = makeFake(v);
  return out;
});
const ADMIN_ID = '64b0000000000000000000a1';
jest.mock('../src/models/Admin', () => ({
  exists: jest.fn(async () => null),
  findById: jest.fn((id) => {
    const v = String(id) === '64b0000000000000000000a1' ? { _id: id, username: 'admin', watch_only: false } : null;
    return { select: () => ({ lean: async () => v }) };
  }),
}));

const fs = require('fs');
const path = require('path');
const express = require('express');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const { WebSocketServer } = require('ws');
const models = require('../src/cashEq/models');
const cashSwitch = require('../src/cashEq/switch');
const instruments = require('../src/cashEq/instruments');
const feedModule = require('../src/cashEq/feed');

const { CashFeed, parseMessage } = feedModule;
const ADMIN = jwt.sign({ id: ADMIN_ID, role: 'admin' }, process.env.JWT_SECRET);
const auth = { Authorization: `Bearer ${ADMIN}` };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 2000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (await fn()) return true; await wait(10); }
  throw new Error('timed out');
}

/** Kite full-mode packet (184 bytes) for an NSE stock. */
function fullPacket(token, ltp, { bid, ask, open = ltp, high = ltp, low = ltp, close = ltp, volume = 1000, buys, sells, lastTradeTs = 1762160000 } = {}) {
  const p = Buffer.alloc(184);
  p.writeInt32BE(token, 0);
  p.writeInt32BE(Math.round(ltp * 100), 4);
  p.writeInt32BE(volume, 16);
  p.writeInt32BE(Math.round(open * 100), 28);
  p.writeInt32BE(Math.round(high * 100), 32);
  p.writeInt32BE(Math.round(low * 100), 36);
  p.writeInt32BE(Math.round(close * 100), 40);
  p.writeInt32BE(lastTradeTs, 44);
  p.writeInt32BE(1762160000, 60);
  const levels = (list, from) => list.forEach(([price, qty, orders = 1], i) => {
    const o = 64 + (from + i) * 12;
    p.writeInt32BE(qty, o);
    p.writeInt32BE(Math.round(price * 100), o + 4);
    p.writeInt16BE(orders, o + 8);
  });
  levels(buys || (bid ? [[bid, 100]] : []), 0);
  levels(sells || (ask ? [[ask, 100]] : []), 5);
  return p;
}
function message(...packets) {
  const parts = [Buffer.alloc(2)];
  parts[0].writeInt16BE(packets.length, 0);
  for (const p of packets) {
    const len = Buffer.alloc(2);
    len.writeInt16BE(p.length, 0);
    parts.push(len, p);
  }
  return Buffer.concat(parts);
}

beforeEach(() => {
  for (const m of Object.values(models)) m.reset();
  for (const k of Object.keys(redisStore)) delete redisStore[k];
  redisStore['cashEq:enabled'] = '1';
  cashSwitch._clearCache();
});

describe('NSE EQ-series stock list', () => {
  const CSV = [
    'instrument_token,exchange_token,tradingsymbol,name,last_price,expiry,strike,tick_size,lot_size,instrument_type,segment,exchange',
    '738561,2885,RELIANCE,"RELIANCE INDUSTRIES",0,,0,0.1,1,EQ,NSE,NSE',
    '408065,1594,INFY,"INFOSYS, LTD",0,,0,0.05,1,EQ,NSE,NSE',
    '2714625,10604,BHARTIARTL-BE,"BHARTI AIRTEL",0,,0,0.05,1,EQ,NSE,NSE',
    '4267265,16669,BAJAJ-AUTO,"BAJAJ AUTO",0,,0,0.5,1,EQ,NSE,NSE',
    '3585,14,656KA30-SG,"SDL KA 6.56% 2030",0,,0,0.01,100,EQ,NSE,NSE',
    '769,3,GOLDSTAR,"GOLDSTAR POWER",0,,0,0.05,11250,EQ,NSE,NSE',
    '256265,1001,NIFTY 50,"NIFTY 50",0,,0,0,0,EQ,INDICES,NSE',
    '12345,48,NIFTY26NOVFUT,"NIFTY",0,2026-11-24,0,0.1,75,FUT,NFO-FUT,NFO',
    '128083204,500325,RELIANCE,"RELIANCE",0,,0,0.05,1,EQ,BSE,BSE',
  ].join('\n');

  test('keeps only NSE EQ-series stocks (no -BE/-SG series, no lots, no indices, no F&O, no BSE; hyphenated names kept)', () => {
    const rows = instruments.parseEqSeries(CSV);
    expect(rows.map((r) => r.tradingsymbol)).toEqual(['RELIANCE', 'INFY', 'BAJAJ-AUTO']);
    expect(rows[1]).toMatchObject({ instrument_token: 408065, name: 'INFOSYS, LTD', tick_size: 0.05 });
  });

  test('a short list is refused (nothing changed)', async () => {
    await expect(instruments.syncInstruments({ csvText: CSV })).rejects.toThrow(/Only 3 EQ stocks/);
    expect(models.EqInstrument.store.size).toBe(0);
  });

  test('sync upserts and marks stocks no longer listed inactive', async () => {
    const head = CSV.split('\n')[0];
    const make = (n, from = 1) => [head, ...Array.from({ length: n }, (_, i) => `${100000 + from + i},1,STK${from + i},"S",0,,0,0.05,1,EQ,NSE,NSE`)].join('\n');
    expect(await instruments.syncInstruments({ csvText: make(600) })).toMatchObject({ stocks: 600, inactivated: 0 });
    expect(await instruments.syncInstruments({ csvText: make(600, 2) })).toMatchObject({ stocks: 600, inactivated: 1 });
    expect((await models.EqInstrument.findOne({ tradingsymbol: 'STK1' })).is_active).toBe(false);
    expect(await models.EqInstrument.countDocuments({ is_active: true })).toBe(600);
  });
});

describe('approved (MTF) list', () => {
  async function seed(symbols) {
    for (const [i, s] of symbols.entries()) await models.EqInstrument.create({ instrument_token: 1000 + i, tradingsymbol: s, name: s });
  }
  const list = (syms) => syms.map((s) => ({ isin: `INE${s}`, tradingsymbol: s, category: 'fo', margin: 25, leverage: 4 }));
  const filler = Array.from({ length: 600 }, (_, i) => `FILL${i}`);

  test('marks approved scripts, reports added/removed, others non-approved', async () => {
    await seed(['RELIANCE', 'INFY', 'SMALLCO', ...filler.slice(0, 5)]);
    const r1 = await instruments.syncMtfList({ json: list(['RELIANCE', 'INFY', 'NOTNSE', ...filler]) });
    expect(r1).toMatchObject({ approved: 7, added: ['FILL0', 'FILL1', 'FILL2', 'FILL3', 'FILL4', 'INFY', 'RELIANCE'], removed: [] });
    expect((await models.EqInstrument.findOne({ tradingsymbol: 'RELIANCE' }))).toMatchObject({ mtf: true, mtf_margin_pct: 25, mtf_category: 'fo' });
    expect((await models.EqInstrument.findOne({ tradingsymbol: 'SMALLCO' })).mtf).toBe(false);
    const r2 = await instruments.syncMtfList({ json: list(['RELIANCE', ...filler]) });
    expect(r2.removed).toEqual(['INFY']);
    expect((await models.EqInstrument.findOne({ tradingsymbol: 'INFY' })).mtf).toBe(false);
  });

  test('a broken or short list keeps yesterday\'s flags', async () => {
    await seed(['RELIANCE', ...filler.slice(0, 5)]);
    await instruments.syncMtfList({ json: list(['RELIANCE', ...filler]) });
    await expect(instruments.syncMtfList({ json: list(['RELIANCE']) })).rejects.toThrow(/only 1 scripts/);
    await expect(instruments.syncMtfList({ json: { error: 'x' } })).rejects.toThrow(/not a list/);
    expect((await models.EqInstrument.findOne({ tradingsymbol: 'RELIANCE' })).mtf).toBe(true);
  });
});

describe('separate Kite feed (fake Kite server)', () => {
  let wss;
  let kiteSockets;
  let received;
  let port;
  beforeEach(async () => {
    kiteSockets = [];
    received = [];
    wss = new WebSocketServer({ port: 0 });
    await new Promise((r) => wss.on('listening', r));
    port = wss.address().port;
    wss.on('connection', (s, req) => {
      kiteSockets.push(s);
      s.reqUrl = req.url;
      s.on('message', (m) => received.push(JSON.parse(m.toString())));
    });
  });
  afterEach(async () => {
    for (const s of kiteSockets) s.terminate(); // ws server close() waits for open sockets
    await new Promise((r) => wss.close(r));
  });

  function makeFeed(lps) {
    const f = new CashFeed();
    f.getAccessToken = async () => 'tok123';
    f.wsUrl = (t) => `ws://127.0.0.1:${port}/?access_token=${t}`;
    f.lps = lps;
    return f;
  }

  test('connects only when switched on and something needs prices; full mode; disconnects when off', async () => {
    const f = makeFeed();
    await f.refresh();
    expect(kiteSockets).toHaveLength(0); // nothing wanted
    f.registerSource('watchlists', async () => [738561, 408065]);
    delete redisStore['cashEq:enabled'];
    cashSwitch._clearCache();
    await f.refresh();
    expect(kiteSockets).toHaveLength(0); // switched off
    redisStore['cashEq:enabled'] = '1';
    cashSwitch._clearCache();
    await f.refresh();
    await until(() => received.length >= 2);
    expect(kiteSockets[0].reqUrl).toContain('access_token=tok123');
    expect(received).toEqual([{ a: 'subscribe', v: [738561, 408065] }, { a: 'mode', v: ['full', [738561, 408065]] }]);

    // Watchlist shrinks: only the removed token is unsubscribed.
    f.registerSource('watchlists', async () => [738561]);
    await f.refresh();
    await until(() => received.length >= 3);
    expect(received[2]).toEqual({ a: 'unsubscribe', v: [408065] });

    delete redisStore['cashEq:enabled'];
    cashSwitch._clearCache();
    await f.refresh();
    await until(() => kiteSockets[0].readyState !== 1);
    expect(f.status().connected).toBe(false);
  });

  test('cap: held/pending first, then watchlists, then screens; extra left out', async () => {
    const f = makeFeed();
    const many = Array.from({ length: 900 }, (_, i) => 500000 + i);
    f.registerSource('watchlists', async () => many, 50);
    f.registerSource('held', async () => [111, 222], 10);
    const wanted = await f.wantedTokens();
    expect(wanted).toHaveLength(feedModule.MAX_TOKENS);
    expect(wanted.slice(0, 3)).toEqual([111, 222, 500000]);
    expect(f.status().left_out_by_cap).toBe(902 - feedModule.MAX_TOKENS);
    expect(await f.hasRoomFor(111)).toBe(true);
    expect(await f.hasRoomFor(999999)).toBe(false);
  });

  test('ticks go only to viewers of those stocks, as cash_ticks; nothing else of F&O is touched', async () => {
    const calls = [];
    // Any use of livePriceService other than broadcastToUser fails the test.
    const lps = new Proxy({ broadcastToUser: (id, data) => calls.push([id, data]) }, {
      get(target, prop) {
        if (prop in target) return target[prop];
        throw new Error(`feed used livePriceService.${String(prop)}`);
      },
    });
    const f = makeFeed(lps);
    f.registerSource('watchlists', async () => [738561, 408065]);
    f.setInterest('viewerA', [738561]);
    f.setInterest('viewerB', [999]);
    await f.refresh();
    await until(() => received.length >= 2);
    kiteSockets[0].send(message(fullPacket(738561, 2912.8, { bid: 2912.4, ask: 2912.8, close: 2890.95 }), fullPacket(408065, 1488.05)));
    kiteSockets[0].send(Buffer.from([0])); // heartbeat
    await until(() => f.quotes.size === 2);
    expect(f.getQuotes([738561])[0]).toMatchObject({ last_price: 2912.8, bid_price: 2912.4, ask_price: 2912.8, close: 2890.95, change: 21.85, change_percent: 0.76 });
    expect(f.push()).toBe(1);
    expect(calls).toEqual([['viewerA', { type: 'cash_ticks', data: [expect.objectContaining({ instrument_token: 738561 })] }]]);
    expect(f.push()).toBe(0); // nothing new
    f.stop('test');
  });

  test('Kite closing before any price: backs off instead of retrying every refresh', async () => {
    wss.on('connection', (s) => s.close());
    const f = makeFeed();
    f.registerSource('watchlists', async () => [738561]);
    await f.refresh();
    await until(() => f.fails === 1);
    expect(f.nextConnectAt).toBeGreaterThan(Date.now() + 20000);
    await f.refresh();
    expect(kiteSockets).toHaveLength(1); // no second connection yet
  });

  test('parser: 5-level market depth, day volume and last trade time (low-volume fill rules need them)', () => {
    const [t] = parseMessage(message(fullPacket(1, 100, {
      volume: 54321, lastTradeTs: 1762150000,
      buys: [[99.95, 120, 3], [99.9, 40], [99.8, 500]], sells: [[100.05, 75, 2], [100.2, 10]],
    })));
    expect(t).toMatchObject({ volume: 54321, last_trade_ts: 1762150000, bid_price: 99.95, ask_price: 100.05 });
    expect(t.depth).toEqual({
      buy: [{ price: 99.95, qty: 120, orders: 3 }, { price: 99.9, qty: 40, orders: 1 }, { price: 99.8, qty: 500, orders: 1 }],
      sell: [{ price: 100.05, qty: 75, orders: 2 }, { price: 100.2, qty: 10, orders: 1 }],
    });
  });

  test('parser: heartbeats and short frames give nothing', () => {
    expect(parseMessage(Buffer.from([0]))).toEqual([]);
    expect(parseMessage(Buffer.alloc(0))).toEqual([]);
  });
});

describe('routes: search, watchlist, prices', () => {
  const app = express();
  app.use(express.json());
  app.use('/api/cash-eq', require('../src/cashEq/routes'));

  beforeEach(async () => {
    feedModule.quotes.clear();
    feedModule.interest.clear();
    feedModule.sources = [];
    feedModule.registerSource('watchlists', () => models.EqWatchlist.distinct('instrument_token'), 50);
    feedModule.refresh = async () => {}; // no network in route tests
    await models.EqInstrument.create({ instrument_token: 738561, tradingsymbol: 'RELIANCE', name: 'RELIANCE INDUSTRIES', mtf: true });
    await models.EqInstrument.create({ instrument_token: 408065, tradingsymbol: 'INFY', name: 'INFOSYS' });
    await models.EqInstrument.create({ instrument_token: 1, tradingsymbol: 'OLDCO', name: 'OLD', is_active: false });
  });

  test('search: symbol prefix, then name; inactive stocks hidden', async () => {
    const r = await request(app).get('/api/cash-eq/instruments/search?q=rel').set(auth).expect(200);
    expect(r.body.data.map((x) => x.tradingsymbol)).toEqual(['RELIANCE']);
    expect(r.body.data[0].mtf).toBe(true);
    const byName = await request(app).get('/api/cash-eq/instruments/search?q=infosys').set(auth).expect(200);
    expect(byName.body.data.map((x) => x.tradingsymbol)).toEqual(['INFY']);
    const old = await request(app).get('/api/cash-eq/instruments/search?q=old').set(auth).expect(200);
    expect(old.body.data).toEqual([]);
  });

  test('watchlist: add, A→Z with approved flag and quote, remove; unknown stock refused', async () => {
    await request(app).post('/api/cash-eq/watchlist').set(auth).send({ instrument_token: 738561 }).expect(201);
    await request(app).post('/api/cash-eq/watchlist').set(auth).send({ instrument_token: 408065 }).expect(201);
    await request(app).post('/api/cash-eq/watchlist').set(auth).send({ instrument_token: 408065 }).expect(200);
    await request(app).post('/api/cash-eq/watchlist').set(auth).send({ instrument_token: 1 }).expect(404);
    feedModule.quotes.set(738561, { instrument_token: 738561, last_price: 2912.8 });
    const list = await request(app).get('/api/cash-eq/watchlist').set(auth).expect(200);
    expect(list.body.data.map((x) => [x.tradingsymbol, x.mtf, x.quote?.last_price ?? null])).toEqual([['INFY', false, null], ['RELIANCE', true, 2912.8]]);
    await request(app).delete('/api/cash-eq/watchlist/408065').set(auth).expect(200);
    expect((await request(app).get('/api/cash-eq/watchlist').set(auth)).body.data).toHaveLength(1);
  });

  test('stream: registers the caller for live prices of known stocks only', async () => {
    const r = await request(app).post('/api/cash-eq/stream').set(auth).send({ tokens: '738561,408065,424242' }).expect(200);
    expect(r.body.data.streaming).toBe(2);
    expect([...feedModule.interest.get(ADMIN_ID).tokens].sort()).toEqual([408065, 738561]);
  });

  test('feed status and sync are admin-only', async () => {
    const client = jwt.sign({ id: '64b0000000000000000000c1', role: 'cash_client' }, process.env.JWT_SECRET);
    await request(app).get('/api/cash-eq/feed/status').set({ Authorization: `Bearer ${client}` }).expect(403);
    const s = await request(app).get('/api/cash-eq/feed/status').set(auth).expect(200);
    expect(s.body.data).toMatchObject({ stocks: 2, approved: 1, feed: expect.objectContaining({ cap: feedModule.MAX_TOKENS }) });
  });
});

describe('code-level separation from F&O', () => {
  const dir = path.join(__dirname, '..', 'src', 'cashEq');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.js'));
  const src = Object.fromEntries(files.map((f) => [f, fs.readFileSync(path.join(dir, f), 'utf8')]));

  test('equity code only requires its own files, libraries, and a short list of F&O read-only helpers', () => {
    const ALLOWED_OUTSIDE = new Set([
      '../models/Admin', '../models/Master', '../models/User', // username checks / admin sign-in (read only)
      '../services/redisService', // on/off switch
      '../services/kiteService', // stored Kite access token (read only)
      '../config/practice', // never run on the practice server
    ]);
    const LIBS = new Set(['mongoose', 'express', 'bcryptjs', 'jsonwebtoken', 'crypto', 'ws', 'axios', 'zlib', 'util', 'node-cron']);
    const bad = [];
    for (const [f, code] of Object.entries(src)) {
      for (const [, mod] of code.matchAll(/require\(\s*['"]([^'"]+)['"]\s*\)/g)) {
        if (mod.startsWith('./') || LIBS.has(mod) || ALLOWED_OUTSIDE.has(mod)) continue;
        bad.push(`${f}: ${mod}`);
      }
    }
    expect(bad).toEqual([]);
  });

  test('equity code never writes to an F&O model', () => {
    const writes = /\b(Admin|Master|User)\.(create|insertMany|update\w*|replaceOne|delete\w*|findOneAndUpdate|findByIdAndUpdate|bulkWrite)\(/;
    for (const [f, code] of Object.entries(src)) expect({ f, write: writes.test(code) }).toEqual({ f, write: false });
  });

  test('no F&O file requires equity code except index.js and authController.js', () => {
    const root = path.join(__dirname, '..', 'src');
    const hits = [];
    const walk = (d) => {
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) { if (e.name !== 'cashEq' && e.name !== 'node_modules') walk(p); } else if (e.name.endsWith('.js') && /cashEq/.test(fs.readFileSync(p, 'utf8'))) {
          hits.push(path.relative(root, p).replace(/\\/g, '/'));
        }
      }
    };
    walk(root);
    expect(hits.sort()).toEqual(['controllers/authController.js', 'index.js']);
  });
});
