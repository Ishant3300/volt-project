'use strict';

// Equity M8 — separation proof, part 2, on a REAL MongoDB (a throwaway replica set in this
// PC's memory — see helpers/cashEqLocalMongo.js; it can never reach the live database).
//
//   A. The F&O weekly settlement (the real settlementService) gives byte-identical results
//      in every F&O collection with and without a busy equity book in the same database
//      (equity masters/clients, a confirmed equity month-end, live equity orders filled in
//      real transactions, money entries).
//   B. The F&O settlement doesn't change a single equity document.
//   C. Equity orders on real MongoDB: transactions, concurrent orders on one thin stock never
//      over-fill and never share a trade number.
//
//   RUN_CASHEQ_PROOF=1 npx jest tests/cashEqSettlement.integration.test.js
//
// The F&O scenario below is copied from tests/settlement.integration.test.js (seedScenario).

const { startLocalMongo, stopLocalMongo } = require('./helpers/cashEqLocalMongo'); // first: blanks every Mongo URI

const run = process.env.RUN_CASHEQ_PROOF === '1';
const describeProof = run ? describe : describe.skip;

jest.mock('../src/cashEq/engine', () => ({ ...jest.requireActual('../src/cashEq/engine'), marketOpen: jest.fn(() => true) }));

const mongoose = require('mongoose');
const BrokerageSettings = require('../src/models/BrokerageSettings');
const KiteInstrument = require('../src/models/KiteInstrument');
const Master = require('../src/models/Master');
const SettlementFence = require('../src/models/SettlementFence');
const SettlementHistory = require('../src/models/SettlementHistory');
const SettlementRun = require('../src/models/SettlementRun');
const Trade = require('../src/models/Trade');
const TradeWriteLease = require('../src/models/TradeWriteLease');
const Transaction = require('../src/models/Transaction');
const User = require('../src/models/User');
const ComexRate = require('../src/models/ComexRate');
const metricsEngine = require('../src/services/metricsEngine');
const livePriceService = require('../src/services/livePriceService');
const settlementService = require('../src/services/settlementService');
const { indiaDayRangeUtc, toIndiaDateOnly } = require('../src/utils/settlementDates');

const eqModels = require('../src/cashEq/models');
const feed = require('../src/cashEq/feed');
const orders = require('../src/cashEq/orders');
const monthEnd = require('../src/cashEq/monthEnd');

jest.setTimeout(240_000);

/* ------------------------------------------------ F&O scenario (copied) */

function resetProcessCaches() {
  metricsEngine._userCache.clear();
  metricsEngine._tokenToUsers.clear();
  metricsEngine._metricsCache.clear();
  metricsEngine._ltpMap.clear();
  metricsEngine._bidMap.clear();
  metricsEngine._askMap.clear();
  metricsEngine._brokerageRules = [];
  metricsEngine._kiteMap = {};
  metricsEngine._masterParentMap = {};
  metricsEngine._masterChildrenMap = {};
  metricsEngine._settledTokens = null;
  metricsEngine._appliedSettlementRunId = null;
  metricsEngine._settlementSyncPromise = null;
  metricsEngine._lastSettlementCheckAt = 0;
  metricsEngine.livePriceService = livePriceService;
  metricsEngine._initialized = true;
  livePriceService.latestPrices.clear();
  if (livePriceService._settlementPrices) livePriceService._settlementPrices.clear();
}

async function clearDatabase() {
  const db = mongoose.connection.db;
  for (const c of await db.listCollections().toArray()) await db.collection(c.name).deleteMany({});
  resetProcessCaches();
  settlementService.resetState();
  orders._stocks.clear();
  orders.openTokens.clear();
  orders.clearSettingsCache();
  feed.quotes.clear();
}

async function seedScenario(prefix) {
  const periodKey = '2026-07-31';
  const tradingDate = toIndiaDateOnly(periodKey);
  const cutoff = indiaDayRangeUtc(tradingDate).end;
  const serverId = new mongoose.Types.ObjectId();
  const adminId = new mongoose.Types.ObjectId();
  const master = await Master.create({
    name: `Integration Master ${prefix}`, username: `it_master_${prefix}`, password: 'not-used', credits: 1_000_000, equity: 1_000_000,
    server_id: serverId, admin_id: adminId, exchanges_allowed: ['NFO-FUT', 'MCX-FUT'],
  });
  const WALLET_FUNDING = 100_000;
  const walletForUser = (i) => {
    if (i === 1) return { NSE: WALLET_FUNDING - 600, MCX: WALLET_FUNDING, GLOBAL: 0 };
    if (i === 2) return { NSE: WALLET_FUNDING, MCX: WALLET_FUNDING - 4000, GLOBAL: 0 };
    return { NSE: WALLET_FUNDING, MCX: WALLET_FUNDING, GLOBAL: 0 };
  };
  const userPayload = (i) => ({
    name: `Integration User ${i}`, username: `it_user_${prefix}_${i}`, password: 'not-used', credits: 100_000, equity: 100_000, settled_pnl: 0,
    server_id: serverId, master_id: master._id, wallet: walletForUser(i),
    exchanges_allowed: [
      { exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'IT' },
      { exchange_name: 'MCX-FUT', turnover: true, lot: false, group_name: 'IT' },
    ],
  });
  const users = await User.create([userPayload(1), userPayload(2), userPayload(3)]);
  const nfoToken = `${prefix.slice(-6)}01`;
  const mcxToken = `${prefix.slice(-6)}02`;
  const instruments = await KiteInstrument.create([
    {
      instrument_token: nfoToken, exchange_token: `${prefix.slice(-6)}11`, tradingsymbol: 'NIFTY26AUGFUT', name: 'NIFTY', raw_name: 'NIFTY',
      display_name: 'NIFTY FUT Aug 2026', last_price: 111, settlement_price: 130, settlement_price_date: tradingDate,
      settlement_price_source: 'NSE_OFFICIAL_BHAVCOPY_TEST', ohlc_close: 130, expiry: new Date('2026-08-25T00:00:00.000Z'),
      strike: 0, tick_size: 0.05, lot_size: 25, instrument_type: 'FUT', segment: 'NFO-FUT', exchange: 'NFO',
    },
    {
      instrument_token: mcxToken, exchange_token: `${prefix.slice(-6)}12`, tradingsymbol: 'GOLD26AUGFUT', name: 'GOLD', raw_name: 'GOLD',
      display_name: 'GOLD FUT Aug 2026', last_price: 190, settlement_price: 180, settlement_price_date: tradingDate,
      settlement_price_source: 'MCX_OFFICIAL_BHAVCOPY_CLOSE_TEST', ohlc_close: 180, expiry: new Date('2026-08-31T00:00:00.000Z'),
      strike: 0, tick_size: 1, lot_size: 10, instrument_type: 'FUT', segment: 'MCX-FUT', exchange: 'MCX',
    },
  ]);
  const executedAt = new Date(cutoff.getTime() - (8 * 60 * 60 * 1000));
  const createdAt = new Date(executedAt.getTime() - 1000);
  const t = (u, inst, side, qty, price, pnl, k) => ({
    user_id: users[u]._id, master_id: master._id, admin_id: adminId, instrument_token: inst === 0 ? nfoToken : mcxToken,
    tradingsymbol: instruments[inst].tradingsymbol, exchange: inst === 0 ? 'NFO' : 'MCX', transaction_type: side, quantity: qty, price,
    order_type: 'MARKET', status: 'completed', executed_at: new Date(executedAt.getTime() + k * 1000), executed_price: price,
    executed_quantity: qty, pnl, createdAt: new Date(createdAt.getTime() + k * 1000), updatedAt: new Date(createdAt.getTime() + k * 1000),
  });
  await Trade.create([t(0, 0, 'BUY', 10, 100, 0, 0), t(0, 0, 'SELL', 4, 120, 80, 1), t(1, 1, 'SELL', 20, 200, 0, 2), t(2, 0, 'BUY', 5, 50, 0, 3), t(2, 0, 'SELL', 5, 55, 25, 4)]);
  await Trade.create({
    user_id: users[0]._id, master_id: master._id, admin_id: adminId, instrument_token: nfoToken, tradingsymbol: instruments[0].tradingsymbol,
    exchange: 'NFO', transaction_type: 'BUY', quantity: 1, price: 90, order_type: 'LIMIT', status: 'pending', executed_at: null,
    executed_price: null, executed_quantity: 0, createdAt: new Date(createdAt.getTime() + 5000), updatedAt: new Date(createdAt.getTime() + 5000),
  });
  return { tradingDate, users };
}

const runSettlement = (tradingDate) => settlementService.runSettlement({
  tradingDate, priceDates: { nse: tradingDate, mcx: tradingDate }, refreshPrices: false, applySettlementPrices: true, waitForCompletion: true,
});

/* ------------------------------------------------ equity book */

const pct = (intraday, carry) => ({ mode: 'PCT', intraday, carry, min_rate: 0, higher_side_only: false });
const BIG = 738561;
const THIN = 4632577;
const ADMIN = { role: 'admin', id: '64b0000000000000000000a1', username: 'admin', watchOnly: false };

async function seedEquity() {
  const top = await eqModels.EqMaster.create({
    name: 'Eq Top', username: 'EQTOPPROOF', password: 'x', per_script_limit: 5e6, total_limit: 5e7,
    brokerage_mtf: pct(0.02, 0.1), brokerage_non: pct(0.03, 0.2), interest_mtf_pct: 12, interest_non_pct: 15, pnl_share: 60, brokerage_share: 50, interest_share: 50,
  });
  const clients = [];
  for (let i = 1; i <= 4; i++) {
    clients.push(await eqModels.EqClient.create({
      name: `Eq Client ${i}`, username: `EQPROOF${i}`, password: 'x', master_id: top._id, per_script_limit: 5e6, total_limit: 5e7,
      opening_balance: 100000 * i, opening_type: 'Cr', brokerage_mtf: pct(0.03, 0.2), brokerage_non: pct(0.05, 0.4), interest_mtf_pct: 18, interest_non_pct: 21,
    }));
  }
  await eqModels.EqInstrument.create([
    { instrument_token: BIG, tradingsymbol: 'RELIANCE', name: 'RELIANCE', tick_size: 0.05, mtf: true },
    { instrument_token: THIN, tradingsymbol: 'SMALLCO', name: 'SMALLCO', tick_size: 0.05, mtf: false },
  ]);
  // July history + a confirmed equity month-end for July (the same month the F&O week ends in).
  let seq = 0;
  for (const [i, c] of clients.entries()) {
    await eqModels.EqTrade.create({
      seq: ++seq, client_id: c._id, order_id: new mongoose.Types.ObjectId(), instrument_token: BIG, tradingsymbol: 'RELIANCE', mtf: true,
      side: 'B', qty: 100 * (i + 1), price: 1400 + i, date: '2026-07-10', add_time: '2026-07-10 10:00:00',
    });
    await eqModels.EqLedgerEntry.create({ client_id: c._id, date: '2026-07-15', kind: 'DEPOSIT', amount: 25000, narration: 'proof' });
  }
  await eqModels.EqCounter.create({ _id: 'trade', seq });
  const bhav = ['SYMBOL, SERIES, DATE1, PREV_CLOSE, OPEN_PRICE, HIGH_PRICE, LOW_PRICE, LAST_PRICE, CLOSE_PRICE, AVG_PRICE, TTL_TRD_QNTY, TURNOVER_LACS, NO_OF_TRADES, DELIV_QTY, DELIV_PER',
    'RELIANCE, EQ, x, 1, 1, 1, 1, 1, 1450.00, 1, 1, 1, 1, 1, 1',
    ...Array.from({ length: 150 }, (_, k) => `FILL${k}, EQ, x, 1, 1, 1, 1, 1, 10.00, 1, 1, 1, 1, 1, 1`)].join('\n');
  const july = await monthEnd.preview(ADMIN, { month: '2026-07' }, { download: async (d) => (d === '2026-07-31' ? bhav : null) });
  await monthEnd.confirm(ADMIN, july.run._id);
  // Today: live equity orders filled in real transactions (liquid fill + thin-stock partial + paced remainder).
  await eqModels.EqSettings.create({ _id: 'liquidity', values: { fill_interval_sec: 0 } });
  orders.clearSettingsCache();
  const now = Math.floor(Date.now() / 1000);
  const q = (token, ltp, volume, levels) => feed.quotes.set(token, {
    instrument_token: token, last_price: ltp, close: ltp, volume, last_trade_ts: now,
    depth: { sell: levels.map(([p, n]) => ({ price: p, qty: n, orders: 1 })), buy: [{ price: ltp - 0.05, qty: 1000, orders: 1 }] },
    bid_price: ltp - 0.05, ask_price: levels[0][0],
  });
  q(BIG, 1460, 5e6, [[1460.05, 400], [1460.1, 1000]]);
  q(THIN, 48.75, 3000, [[48.8, 5000]]);
  const asClient = (c) => ({ role: 'cash_client', id: String(c._id), username: c.username, watchOnly: false, doc: c });
  await orders.placeOrder(asClient(clients[0]), { instrument_token: BIG, side: 'B', qty: 600, order_type: 'MARKET' });
  await orders.placeOrder(asClient(clients[1]), { instrument_token: THIN, side: 'B', qty: 2000, order_type: 'LIMIT', limit_price: 49 });
  q(THIN, 48.75, 9000, [[48.8, 5000]]);
  await orders.processStock(THIN);
  await orders.placeOrder(asClient(clients[2]), { instrument_token: BIG, side: 'S', qty: 50, order_type: 'MARKET' });
  return { clients };
}

/* ------------------------------------------------ snapshots */

const VOLATILE_KEYS = new Set(['lock_owner', 'owner', 'lease_owner', 'heartbeat_at', 'lease_expires_at', '__v']);

/** All F&O collections (everything not eqcash_*), canonical: ids by first appearance, run-time dates → NOW. */
async function fnoSnapshot() {
  const db = mongoose.connection.db;
  const names = (await db.listCollections().toArray()).map((c) => c.name).filter((n) => !n.startsWith('eqcash_') && !n.startsWith('system.')).sort();
  const ids = new Map();
  const label = (id) => { const k = String(id); if (!ids.has(k)) ids.set(k, `ID${ids.size}`); return ids.get(k); };
  const started = Date.now() - 30 * 60 * 1000;
  const norm = (v, key) => {
    if (VOLATILE_KEYS.has(key)) return 'VOLATILE';
    if (v instanceof mongoose.Types.ObjectId || v?._bsontype === 'ObjectId') return label(v);
    if (v instanceof Date) return v.getTime() >= started ? 'NOW' : v.toISOString();
    if (Array.isArray(v)) return v.map((x) => norm(x, key));
    if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map((k) => [k, norm(v[k], k)]));
    return v;
  };
  const out = {};
  for (const n of names) out[n] = (await db.collection(n).find({}).sort({ _id: 1 }).toArray()).map((d) => norm(d, ''));
  return out;
}

async function equitySnapshot() {
  const db = mongoose.connection.db;
  const names = (await db.listCollections().toArray()).map((c) => c.name).filter((n) => n.startsWith('eqcash_')).sort();
  const out = {};
  for (const n of names) out[n] = JSON.stringify(await db.collection(n).find({}).sort({ _id: 1 }).toArray());
  return out;
}

/* ------------------------------------------------ the proof */

describeProof('equity separation on a real MongoDB (local, throwaway)', () => {
  beforeAll(async () => {
    await startLocalMongo(`cashEq_proof_${process.pid}`);
    for (const m of [KiteInstrument, Master, SettlementFence, SettlementHistory, SettlementRun, Trade, TradeWriteLease, Transaction, User, ComexRate, BrokerageSettings]) await m.syncIndexes();
    for (const m of Object.values(eqModels)) await m.syncIndexes();
  });
  afterAll(stopLocalMongo);

  test('A+B: weekly settlement identical with and without a busy equity book; equity untouched by it', async () => {
    // Run 1: F&O only.
    await clearDatabase();
    const s1 = await seedScenario('eqproof');
    const r1 = await runSettlement(s1.tradingDate);
    expect(r1.success).toBe(true);
    const fnoOnly = await fnoSnapshot();

    // Run 2: the same F&O week, with equity activity before and around it.
    await clearDatabase();
    const eq = await seedEquity();
    const s2 = await seedScenario('eqproof');
    const equityBefore = await equitySnapshot();
    const r2 = await runSettlement(s2.tradingDate);
    expect(r2.success).toBe(true);
    const withEquity = await fnoSnapshot();
    const equityAfter = await equitySnapshot();

    // The equity book really is there and busy.
    expect(await eqModels.EqTrade.countDocuments({})).toBeGreaterThanOrEqual(8);
    expect(await eqModels.EqMonthRun.countDocuments({ status: 'CONFIRMED' })).toBe(1);
    expect(eq.clients).toHaveLength(4);

    // A: every F&O collection byte-identical (after the id/now normalisation above).
    expect(Object.keys(withEquity)).toEqual(Object.keys(fnoOnly));
    for (const name of Object.keys(fnoOnly)) {
      expect({ name, docs: JSON.stringify(withEquity[name]) }).toEqual({ name, docs: JSON.stringify(fnoOnly[name]) });
    }
    // The settlement itself did real work (not a vacuous comparison).
    expect(fnoOnly.settlementruns.length).toBe(1);
    expect(fnoOnly.settlementhistories.length).toBeGreaterThan(0);

    // B: the F&O settlement didn't touch a single equity document.
    expect(equityAfter).toEqual(equityBefore);
  });

  test('C: equity fills on real MongoDB — transactions, no over-fill, unique trade numbers under concurrency', async () => {
    await clearDatabase();
    const { clients } = await seedEquity();
    const now = Math.floor(Date.now() / 1000);
    // Thin stock, day volume 20,000 → all our clients together may fill 2,000 today.
    feed.quotes.set(THIN, {
      instrument_token: THIN, last_price: 48.75, close: 48.75, volume: 20000, last_trade_ts: now,
      depth: { sell: [{ price: 48.8, qty: 50000, orders: 1 }], buy: [{ price: 48.7, qty: 100, orders: 1 }] }, bid_price: 48.7, ask_price: 48.8,
    });
    orders._stocks.clear();
    const asClient = (c) => ({ role: 'cash_client', id: String(c._id), username: c.username, watchOnly: false, doc: c });
    const placed = await Promise.all(Array.from({ length: 12 }, (_, i) => orders.placeOrder(asClient(clients[i % 4]), { instrument_token: THIN, side: 'B', qty: 500, order_type: 'LIMIT', limit_price: 49 })));
    expect(placed.every((p) => p.ok)).toBe(true);
    const today = require('../src/cashEq/engine').istNow().date;
    const thinToday = await eqModels.EqTrade.find({ instrument_token: THIN, date: today }).lean();
    const filledToday = thinToday.reduce((a, t) => a + t.qty, 0);
    expect(filledToday).toBeLessThanOrEqual(2000); // 10 % of the day's volume, all clients together
    const allTrades = await eqModels.EqTrade.find({}).lean();
    expect(new Set(allTrades.map((t) => t.seq)).size).toBe(allTrades.length); // trade numbers unique
    for (const o of await eqModels.EqOrder.find({ instrument_token: THIN }).lean()) {
      const sum = thinToday.filter((t) => String(t.order_id) === String(o._id)).reduce((a, t) => a + t.qty, 0);
      expect({ order: String(o._id), filled: o.filled_qty }).toEqual({ order: String(o._id), filled: sum }); // order = its trades
      expect(o.filled_qty).toBeLessThanOrEqual(o.qty);
    }
  });
});
