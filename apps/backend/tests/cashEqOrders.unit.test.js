// Equity M4: orders with the low-volume fill rules — fills only against the real book
// (depth), a platform-wide share of the exchange volume, illiquid guard, price collar;
// limits, no short selling, cancel/modify, day-end expiry, and who may see/act on what.

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
jest.mock('../src/cashEq/txn', () => ({ withTxn: (fn) => fn(null) }));
jest.mock('../src/cashEq/engine', () => ({ ...jest.requireActual('../src/cashEq/engine'), marketOpen: jest.fn(() => true) }));
const ADMIN_ID = '64b0000000000000000000a1';
jest.mock('../src/models/Admin', () => ({
  exists: jest.fn(async () => null),
  findById: jest.fn((id) => {
    const v = String(id) === '64b0000000000000000000a1' ? { _id: id, username: 'admin', watch_only: false } : null;
    return { select: () => ({ lean: async () => v }) };
  }),
}));
jest.mock('../src/models/Master', () => ({ exists: jest.fn(async () => null) }));
jest.mock('../src/models/User', () => ({ exists: jest.fn(async () => null) }));

const express = require('express');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const models = require('../src/cashEq/models');
const engine = require('../src/cashEq/engine');
const cashSwitch = require('../src/cashEq/switch');
const feed = require('../src/cashEq/feed');
const liquidity = require('../src/cashEq/liquidity');
const orders = require('../src/cashEq/orders');
const book = require('../src/cashEq/book');

const app = express();
app.use(express.json());
app.use('/api/cash-eq', require('../src/cashEq/routes'));

const L = 1e5;
const CR = 1e7;
const S = liquidity.settingsWith();
const nowSec = () => Math.floor(Date.now() / 1000);
const tok = (id, role) => jwt.sign({ id, role }, process.env.JWT_SECRET);
const ADMIN = { Authorization: `Bearer ${tok(ADMIN_ID, 'admin')}` };

const THIN = 111; // thin stock (non-approved)
const BIG = 222; // liquid stock (approved / MTF)

/** Quote with depth: sells/buys = [[price, qty], ...]. */
function quote(token, { ltp, volume, sells = [], buys = [], close = ltp, lastTradeAgo = 5 }) {
  return {
    instrument_token: token, last_price: ltp, close, volume, last_trade_ts: nowSec() - lastTradeAgo,
    depth: { sell: sells.map(([price, qty]) => ({ price, qty, orders: 1 })), buy: buys.map(([price, qty]) => ({ price, qty, orders: 1 })) },
    bid_price: buys[0]?.[0], ask_price: sells[0]?.[0],
  };
}
const setQuote = (q) => feed.quotes.set(q.instrument_token, q);

let master;
let clientA;
let clientB;
const asClient = (c) => ({ Authorization: `Bearer ${c.token}` });
const place = (headers, body) => request(app).post('/api/cash-eq/orders').set(headers).send(body);
const pending = () => new Promise((r) => setTimeout(r, 0));

beforeEach(async () => {
  for (const m of Object.values(models)) m.reset();
  for (const k of Object.keys(redisStore)) delete redisStore[k];
  redisStore['cashEq:enabled'] = '1';
  cashSwitch._clearCache();
  orders.clearSettingsCache();
  orders._stocks.clear();
  orders.openTokens.clear();
  feed.quotes.clear();
  feed.refresh = async () => {};
  feed.lps = null;
  engine.marketOpen.mockReturnValue(true);

  const rates = {
    brokerage_mtf: { mode: 'PCT', intraday: 0.02, carry: 0.1 }, brokerage_non: { mode: 'PCT', intraday: 0.05, carry: 0.3 },
    interest_mtf_pct: 15, interest_non_pct: 20,
  };
  master = await models.EqMaster.create({
    name: 'M', username: 'EQMASTER', password: 'x', per_script_limit: 25 * L, total_limit: 2 * CR, ...rates,
    pnl_share: 40, brokerage_share: 50, interest_share: 50,
  });
  const mk = async (username) => {
    const c = await models.EqClient.create({ name: username, username, password: 'x', master_id: master._id, per_script_limit: 25 * L, total_limit: 2 * CR, ...rates });
    const t = tok(String(c._id), 'cash_client');
    c.active_token = t;
    await c.save();
    return { id: String(c._id), token: t };
  };
  clientA = await mk('EQA001');
  clientB = await mk('EQB001');
  await models.EqInstrument.create({ instrument_token: THIN, tradingsymbol: 'THINCO', name: 'THIN CO', tick_size: 0.05, mtf: false });
  await models.EqInstrument.create({ instrument_token: BIG, tradingsymbol: 'BIGCO', name: 'BIG CO', tick_size: 0.05, mtf: true });
});

describe('liquidity rules (pure)', () => {
  const q = quote(1, { ltp: 100, volume: 1e6, sells: [[100.05, 500], [100.1, 1000], [103, 9999]], buys: [[99.95, 300]] });
  test('depth sweep: level by level at each level\'s price; collar stops at 2 % from LTP', () => {
    const r = liquidity.sweep({ side: 'B', quote: q, wantQty: 5000, capQty: 1e9, s: S });
    expect(r.fills).toEqual([{ qty: 500, price: 100.05 }, { qty: 1000, price: 100.1 }]); // 103 is beyond 102
    expect(r.avgPrice).toBe(100.08);
  });
  test('limit price and depth already taken by our other orders are respected', () => {
    expect(liquidity.sweep({ side: 'B', quote: q, wantQty: 5000, capQty: 1e9, limitPrice: 100.05, s: S }).qty).toBe(500);
    const used = new Map([[100.05, 400]]);
    expect(liquidity.sweep({ side: 'B', quote: q, wantQty: 300, capQty: 1e9, used, s: S }).fills).toEqual([{ qty: 100, price: 100.05 }, { qty: 200, price: 100.1 }]);
  });
  test('cap limits the fill; sell side takes buy levels', () => {
    expect(liquidity.sweep({ side: 'B', quote: q, wantQty: 5000, capQty: 120, s: S }).qty).toBe(120);
    expect(liquidity.sweep({ side: 'S', quote: q, wantQty: 1000, capQty: 1e9, s: S }).fills).toEqual([{ qty: 300, price: 99.95 }]);
  });
  test('illiquid guard: no depth, no recent trade, wide spread', () => {
    const now = nowSec();
    expect(liquidity.illiquidReason(quote(1, { ltp: 100, volume: 10, buys: [[99, 1]] }), 'B', S, now)).toMatch(/Nobody is selling/);
    expect(liquidity.illiquidReason(quote(1, { ltp: 100, volume: 10, sells: [[100.1, 5]], buys: [[100, 5]], lastTradeAgo: 600 }), 'B', S, now)).toMatch(/No trade in the last 5 minutes/);
    expect(liquidity.illiquidReason(quote(1, { ltp: 100, volume: 10, sells: [[101.5, 5]], buys: [[99, 5]] }), 'B', S, now)).toMatch(/wider than 1 %/);
    expect(liquidity.illiquidReason(quote(1, { ltp: 100, volume: 10, sells: [[100.05, 5]], buys: [[100, 5]] }), 'B', S, now)).toBeNull();
  });
  test('participation budget grows only with volume traded after we started watching', () => {
    const st = liquidity.newStockState('2026-11-04');
    liquidity.onVolume(st, { volume: 5000 }, S);
    expect(st.budget).toBe(0);
    liquidity.onVolume(st, { volume: 15000 }, S);
    expect(st.budget).toBe(1000);
    expect(liquidity.dayRoom(st, { volume: 15000 }, S)).toBe(1500);
  });
});

describe('orders through the routes', () => {
  test('liquid stock: market buy sweeps the depth now, one trade per level, approved rates', async () => {
    setQuote(quote(BIG, { ltp: 100, volume: 2e6, sells: [[100.05, 500], [100.1, 1000]], buys: [[99.95, 500]] }));
    const r = await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 800, order_type: 'MARKET' }).expect(201);
    expect(r.body.data).toMatchObject({ status: 'FILLED', filled_qty: 800, mtf: true });
    expect(r.body.data.filled_value).toBeCloseTo(500 * 100.05 + 300 * 100.1, 6);
    expect(r.body.data.avg_price).toBe(100.0688); // display, 4 decimals
    const trades = [...models.EqTrade.store.values()].map((t) => [t.qty, t.price, t.mtf]);
    expect(trades).toEqual([[500, 100.05, true], [300, 100.1, true]]);
    // Brokerage uses the approved (MTF) carry rate 0.1 %, not the non-approved 0.3 %.
    const client = await models.EqClient.findOne({ _id: clientA.id }).lean();
    const engTrades = await book.loadTrades(clientA.id);
    const calcs = book.calcsFor(client, engTrades);
    expect(calcs.get(engTrades[0].id).brokerage).toBeCloseTo(500 * 100.05 * 0.001, 6);
    expect(client.first_trade_at).toBeTruthy();
  });

  test('thin stock: fills only 10 % of the day\'s volume now; the rest fills step by step as the market trades', async () => {
    setQuote(quote(THIN, { ltp: 50, volume: 5000, sells: [[50.05, 3000], [50.1, 3000]], buys: [[50, 1000]] }));
    const r = await place(asClient(clientA), { instrument_token: THIN, side: 'B', qty: 2000, order_type: 'MARKET' }).expect(201);
    expect(r.body.data).toMatchObject({ status: 'OPEN', filled_qty: 500 });
    expect(r.body.data.reason).toBe('Filled 500 of 2000 — rest filling as the market trades');

    // Exchange trades 10,000 more: 10 % = 1,000 for our orders; day room 1,500 − 500 = 1,000.
    setQuote(quote(THIN, { ltp: 50.05, volume: 15000, sells: [[50.1, 3000]], buys: [[50.05, 1000]] }));
    expect(await orders.processStock(THIN)).toBe(1000);
    // 2,000 more traded: 200 more.
    setQuote(quote(THIN, { ltp: 50.1, volume: 17000, sells: [[50.1, 3000]], buys: [[50.05, 1000]] }));
    expect(await orders.processStock(THIN)).toBe(200);
    const o = await models.EqOrder.findOne({ _id: r.body.data._id }).lean();
    expect(o).toMatchObject({ status: 'OPEN', filled_qty: 1700 });
    // Nothing traded: nothing fills.
    expect(await orders.processStock(THIN)).toBe(0);
  });

  test('the volume share is platform-wide: a second client waits behind the first (oldest first)', async () => {
    setQuote(quote(THIN, { ltp: 50, volume: 1000, sells: [[50.05, 5000]], buys: [[50, 1000]] }));
    await place(asClient(clientA), { instrument_token: THIN, side: 'B', qty: 1000, order_type: 'MARKET' }).expect(201); // 100 now
    await place(asClient(clientB), { instrument_token: THIN, side: 'B', qty: 1000, order_type: 'MARKET' }).expect(201); // day room used up
    const filledOf = async (id) => (await models.EqOrder.find({ client_id: id }).lean())[0].filled_qty;
    expect([await filledOf(clientA.id), await filledOf(clientB.id)]).toEqual([100, 0]);
    setQuote(quote(THIN, { ltp: 50, volume: 4000, sells: [[50.05, 5000]], buys: [[50, 1000]] })); // +3,000 → 300 shared
    await orders.processStock(THIN);
    expect([await filledOf(clientA.id), await filledOf(clientB.id)]).toEqual([400, 0]);
  });

  test('low volume: MARKET refused (saved with the reason), LIMIT accepted', async () => {
    setQuote(quote(THIN, { ltp: 50, volume: 100, sells: [[50.1, 50]], buys: [[50, 50]], lastTradeAgo: 900 }));
    const r = await place(asClient(clientA), { instrument_token: THIN, side: 'B', qty: 10, order_type: 'MARKET' }).expect(400);
    expect(r.body.message).toMatch(/No trade in the last 5 minutes/);
    expect(r.body.data.status).toBe('REJECTED');
    const lim = await place(asClient(clientA), { instrument_token: THIN, side: 'B', qty: 10, order_type: 'LIMIT', limit_price: 49.5 }).expect(201);
    expect(lim.body.data).toMatchObject({ status: 'OPEN', filled_qty: 0 });
    const log = await request(app).get('/api/cash-eq/orders?status=REJECTED').set(asClient(clientA)).expect(200);
    expect(log.body.data).toHaveLength(1);
  });

  test('LIMIT: waits until the book reaches the price, then fills at the book price within the volume share', async () => {
    setQuote(quote(BIG, { ltp: 100, volume: 1e6, sells: [[100.05, 500]], buys: [[99.95, 500]] }));
    const r = await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 300, order_type: 'LIMIT', limit_price: 99.5 }).expect(201);
    expect(r.body.data.filled_qty).toBe(0);
    setQuote(quote(BIG, { ltp: 99.45, volume: 1e6 + 10000, sells: [[99.45, 200], [99.5, 400]], buys: [[99.4, 500]] }));
    await orders.processStock(BIG);
    const o = await models.EqOrder.findOne({ _id: r.body.data._id }).lean();
    expect(o).toMatchObject({ status: 'FILLED', filled_qty: 300 });
    expect([...models.EqTrade.store.values()].map((t) => [t.qty, t.price])).toEqual([[200, 99.45], [100, 99.5]]);
  });

  test('LIMIT price checks: too far from the previous close, wrong tick step', async () => {
    setQuote(quote(BIG, { ltp: 100, volume: 1e6, sells: [[100.05, 500]], buys: [[99.95, 500]] }));
    expect((await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 1, order_type: 'LIMIT', limit_price: 130 }).expect(400)).body.message).toMatch(/more than 20 %/);
    expect((await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 1, order_type: 'LIMIT', limit_price: 99.97 }).expect(400)).body.message).toMatch(/steps of 0.05/);
  });

  test('limits: per-script incl. open buy orders; the message shows the room', async () => {
    setQuote(quote(BIG, { ltp: 1000, volume: 1e7, sells: [[1000.05, 100000]], buys: [[999.95, 100000]] }));
    await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 2000, order_type: 'LIMIT', limit_price: 990 }).expect(201); // 19.8 L reserved
    const r = await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 600, order_type: 'MARKET' }).expect(400); // +6 L > 25 L
    expect(r.body.message).toMatch(/Above the per-script limit for BIGCO: limit 25 L, used 19.8 L, room 5.2 L/);
    await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 500, order_type: 'MARKET' }).expect(201);
  });

  test('no short selling: sell only what is held, minus open sells', async () => {
    setQuote(quote(BIG, { ltp: 100, volume: 1e7, sells: [[100.05, 5000]], buys: [[99.95, 5000]] }));
    expect((await place(asClient(clientA), { instrument_token: BIG, side: 'S', qty: 1, order_type: 'MARKET' }).expect(400)).body.message).toMatch(/No BIGCO shares to sell/);
    await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 100, order_type: 'MARKET' }).expect(201);
    await place(asClient(clientA), { instrument_token: BIG, side: 'S', qty: 60, order_type: 'LIMIT', limit_price: 110 }).expect(201);
    expect((await place(asClient(clientA), { instrument_token: BIG, side: 'S', qty: 41, order_type: 'MARKET' }).expect(400)).body.message).toMatch(/sell at most 40 BIGCO/);
    const s = await place(asClient(clientA), { instrument_token: BIG, side: 'S', qty: 40, order_type: 'MARKET' }).expect(201);
    expect(s.body.data).toMatchObject({ status: 'FILLED', avg_price: 99.95 });
  });

  test('market closed: refused', async () => {
    engine.marketOpen.mockReturnValue(false);
    setQuote(quote(BIG, { ltp: 100, volume: 1e6, sells: [[100.05, 500]], buys: [[99.95, 500]] }));
    expect((await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 1, order_type: 'MARKET' }).expect(400)).body.message).toMatch(/market is closed/);
  });

  test('cancel keeps what filled; modify can make a LIMIT order meet the book', async () => {
    setQuote(quote(THIN, { ltp: 50, volume: 3000, sells: [[50.05, 5000]], buys: [[50, 100]] }));
    const r = await place(asClient(clientA), { instrument_token: THIN, side: 'B', qty: 1000, order_type: 'MARKET' }).expect(201);
    expect(r.body.data.filled_qty).toBe(300);
    const c = await request(app).post(`/api/cash-eq/orders/${r.body.data._id}/cancel`).set(asClient(clientA)).expect(200);
    expect(c.body.data).toMatchObject({ status: 'CANCELLED', filled_qty: 300, reason: 'Cancelled — 300 of 1000 filled' });
    await request(app).post(`/api/cash-eq/orders/${r.body.data._id}/cancel`).set(asClient(clientA)).expect(400);

    setQuote(quote(BIG, { ltp: 100, volume: 1e6, sells: [[100.05, 500]], buys: [[99.95, 500]] }));
    const lim = await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 100, order_type: 'LIMIT', limit_price: 99 }).expect(201);
    const m = await request(app).patch(`/api/cash-eq/orders/${lim.body.data._id}`).set(asClient(clientA)).send({ limit_price: 100.05 }).expect(200);
    expect(m.body.data).toMatchObject({ status: 'FILLED', filled_qty: 100, avg_price: 100.05 });
  });

  test('day end: open orders expire, filled part stays', async () => {
    setQuote(quote(THIN, { ltp: 50, volume: 3000, sells: [[50.05, 5000]], buys: [[50, 100]] }));
    const r = await place(asClient(clientA), { instrument_token: THIN, side: 'B', qty: 1000, order_type: 'MARKET' }).expect(201);
    expect(await orders.expireOpen(engine.istNow().date)).toBe(1);
    const o = await models.EqOrder.findOne({ _id: r.body.data._id }).lean();
    expect(o).toMatchObject({ status: 'EXPIRED', filled_qty: 300, reason: 'Filled 300 of 1000; rest expired at the close' });
  });

  test('who sees what: clients only their own; the master its tree; admin places for a client', async () => {
    setQuote(quote(BIG, { ltp: 100, volume: 1e6, sells: [[100.05, 5000]], buys: [[99.95, 500]] }));
    await place(asClient(clientA), { instrument_token: BIG, side: 'B', qty: 10, order_type: 'MARKET' }).expect(201);
    await place(ADMIN, { client_id: clientB.id, instrument_token: BIG, side: 'B', qty: 5, order_type: 'MARKET' }).expect(201);
    await place(ADMIN, { instrument_token: BIG, side: 'B', qty: 5, order_type: 'MARKET' }).expect(400); // admin must choose the client
    await place(asClient(clientA), { client_id: clientB.id, instrument_token: BIG, side: 'B', qty: 5, order_type: 'MARKET' }).expect(403);
    const mine = await request(app).get('/api/cash-eq/orders').set(asClient(clientA)).expect(200);
    expect(mine.body.data.map((o) => String(o.client_id))).toEqual([clientA.id]);
    const mt = jwt.sign({ id: String(master._id), role: 'cash_master' }, process.env.JWT_SECRET);
    const all = await request(app).get('/api/cash-eq/trades').set({ Authorization: `Bearer ${mt}` }).expect(200);
    expect(all.body.data).toHaveLength(2);
    const fo = jwt.sign({ id: clientA.id, role: 'user' }, process.env.JWT_SECRET);
    await place({ Authorization: `Bearer ${fo}` }, { instrument_token: BIG, side: 'B', qty: 1, order_type: 'MARKET' }).expect(403);
  });

  test('order ticket preview: held, sellable, limit room, rates of the stock\'s category, market-order check', async () => {
    setQuote(quote(THIN, { ltp: 50, volume: 100, sells: [[52, 10]], buys: [[49, 10]] }));
    const p = await request(app).get(`/api/cash-eq/orders/preview?instrument_token=${THIN}`).set(asClient(clientA)).expect(200);
    expect(p.body.data).toMatchObject({
      held: 0, sellable: 0, stock: { mtf: false },
      rates: { category: 'non-approved', interest_pct: 20 },
      limits: { per_script: { limit: 25 * L, used: 0, room: 25 * L }, total: { room: 2 * CR } },
    });
    expect(p.body.data.market.market_buy).toMatch(/wider than 1 %/);
  });

  test('admin settings: change the volume share; bad values refused; clients can\'t', async () => {
    await request(app).patch('/api/cash-eq/settings/liquidity').set(ADMIN).send({ participation_pct: 0 }).expect(400);
    const r = await request(app).patch('/api/cash-eq/settings/liquidity').set(ADMIN).send({ participation_pct: 5, holidays: ['2026-11-24'] }).expect(200);
    expect(r.body.data).toMatchObject({ participation_pct: 5, day_participation_pct: 10, holidays: ['2026-11-24'] });
    await request(app).patch('/api/cash-eq/settings/liquidity').set(asClient(clientA)).send({ participation_pct: 50 }).expect(403);
  });

  test('ticks drive pending fills through the feed listener', async () => {
    setQuote(quote(THIN, { ltp: 50, volume: 1000, sells: [[50.05, 5000]], buys: [[50, 100]] }));
    await place(asClient(clientA), { instrument_token: THIN, side: 'B', qty: 1000, order_type: 'MARKET' }).expect(201); // 100 now
    setQuote(quote(THIN, { ltp: 50, volume: 6000, sells: [[50.05, 5000]], buys: [[50, 100]] })); // +5,000 → 500
    orders.onTicks([{ instrument_token: THIN }]);
    for (let i = 0; i < 20 && (await models.EqOrder.find({}).lean())[0].filled_qty < 600; i++) await pending();
    expect((await models.EqOrder.find({}).lean())[0].filled_qty).toBe(600);
  });
});
