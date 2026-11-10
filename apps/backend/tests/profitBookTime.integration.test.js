'use strict';

// Per-client profit book time (utils/profitBookTime.js) through the real
// order-path check (tradeController _validateFreshStoplossHoldTime) on a
// throwaway database: each client's own minutes, loss closes always allowed,
// 0 = no restriction, the fresh_stoploss toggle no longer matters, and no
// per-script admin row is needed.
//   RUN_SETTLEMENT_INTEGRATION=1 MONGO_URI=... npx jest tests/profitBookTime.integration.test.js

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');

const Trade = require('../src/models/Trade');
const metricsEngine = require('../src/services/metricsEngine');
const { _private: { _validateFreshStoplossHoldTime: holdCheck } } = require('../src/controllers/tradeController');
const { parseProfitBookMinutes, profitBookMinutesOf } = require('../src/utils/profitBookTime');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_pbt_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(60_000);

describe('parseProfitBookMinutes / profitBookMinutesOf', () => {
  test('required whole minutes 0–1440', () => {
    expect(parseProfitBookMinutes(15)).toEqual({ value: 15 });
    expect(parseProfitBookMinutes('0')).toEqual({ value: 0 });
    expect(parseProfitBookMinutes(undefined).error).toMatch(/required/);
    expect(parseProfitBookMinutes('').error).toMatch(/required/);
    expect(parseProfitBookMinutes(2.5).error).toMatch(/whole number/);
    expect(parseProfitBookMinutes(-1).error).toMatch(/between/);
    expect(parseProfitBookMinutes(1441).error).toMatch(/between/);
  });
  test('an account without the field gets the default 10', () => {
    expect(profitBookMinutesOf({})).toBe(10);
    expect(profitBookMinutesOf({ profit_book_minutes: 0 })).toBe(0);
    expect(profitBookMinutesOf({ profit_book_minutes: 15 })).toBe(15);
  });
});

describeIntegration('profit book time in the order path (real MongoDB)', () => {
  const TOKEN = '8801';
  const userId = new mongoose.Types.ObjectId();
  const minutesAgo = (m) => new Date(Date.now() - m * 60_000);

  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_pbt_it_')) throw new Error(`Refusing to test against ${mongoose.connection.name}`);
  });
  beforeEach(async () => {
    await Trade.deleteMany({});
    metricsEngine._bidMap.set(TOKEN, 110); // long bought at 100 → closing at the bid is a profit
    metricsEngine._askMap.set(TOKEN, 111);
    metricsEngine._ltpMap.set(TOKEN, 110);
  });
  afterAll(async () => {
    try {
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_pbt_it_')) await mongoose.connection.dropDatabase();
    } finally { await mongoose.disconnect(); }
  });

  const buy = (at, qty = 10) => Trade.create({
    user_id: userId, master_id: new mongoose.Types.ObjectId(), instrument_token: TOKEN, tradingsymbol: 'TEST26OCTFUT', exchange: 'NFO',
    transaction_type: 'BUY', quantity: qty, price: 100, order_type: 'MARKET', status: 'completed',
    executed_at: at, executed_price: 100, executed_quantity: qty, pnl: 0,
  });
  const sellMarket = (user, qty = 10) => holdCheck(false, user, TOKEN, 'MARKET', 'SELL', 0, 'NFO-FUT', 'NFO', 'TEST', null, qty);

  test("each client's own minutes: 10 vs 15", async () => {
    await buy(minutesAgo(12));
    await expect(sellMarket({ _id: userId, profit_book_minutes: 10 })).resolves.toBeUndefined();
    await expect(sellMarket({ _id: userId, profit_book_minutes: 15 })).rejects.toThrow(/Cannot close this position for 3 more minute\(s\)\. Time restriction: 15 minutes/);
  });

  test('a close at a loss is always allowed', async () => {
    await buy(minutesAgo(1));
    metricsEngine._bidMap.set(TOKEN, 90);
    await expect(sellMarket({ _id: userId, profit_book_minutes: 15 })).resolves.toBeUndefined();
  });

  test('0 minutes = no restriction; the fresh_stoploss toggle no longer matters', async () => {
    await buy(minutesAgo(1));
    await expect(sellMarket({ _id: userId, profit_book_minutes: 0 })).resolves.toBeUndefined();
    await expect(sellMarket({ _id: userId, profit_book_minutes: 10, fresh_stoploss: false })).rejects.toThrow(/Fresh Stop-Loss/);
  });

  test('a profit LIMIT close inside the time is refused too; admin is exempt', async () => {
    await buy(minutesAgo(2));
    await expect(holdCheck(false, { _id: userId, profit_book_minutes: 10 }, TOKEN, 'LIMIT', 'SELL', 105, 'NFO-FUT', 'NFO', 'TEST', null, 10)).rejects.toThrow(/Fresh Stop-Loss/);
    await expect(holdCheck(true, { _id: userId, profit_book_minutes: 10 }, TOKEN, 'MARKET', 'SELL', 0, 'NFO-FUT', 'NFO', 'TEST', null, 10)).resolves.toBeUndefined();
  });
  // ── The live position data the app reads (metricsEngine profit_hold, 10 Nov 2026) must predict
  // this order check exactly: the app locks the close button only when the server would refuse.
  // Same rule as the app's lock (apps/flutter lib/utils/profit_hold.dart, web src/lib/profitHold.ts).
  function predictRefused(pos, { orderType, side, price, qty, bid, ask, now = Date.now() }) {
    const hold = pos.profit_hold;
    if (!hold) return false;
    const closingLong = pos.net_qty > 0 && side === 'SELL';
    const closingShort = pos.net_qty < 0 && side === 'BUY';
    if (!closingLong && !closingShort) return false;
    const closePrice = orderType === 'MARKET' ? (closingLong ? bid : ask) : price;
    if (!(closePrice > 0)) return false;
    const inProfit = closingLong ? closePrice > hold.avg : closePrice < hold.avg;
    if (!inProfit) return false;
    const free = hold.free_qty + hold.lots.filter((l) => Date.parse(l.free_at) <= now).reduce((s, l) => s + l.qty, 0);
    const need = Math.min(qty, Math.abs(pos.net_qty));
    return need > free;
  }

  const fill = (side, at, qty, px) => Trade.create({
    user_id: userId, master_id: new mongoose.Types.ObjectId(), instrument_token: TOKEN, tradingsymbol: 'TEST26OCTFUT', exchange: 'NFO',
    transaction_type: side, quantity: qty, price: px, order_type: 'MARKET', status: 'completed',
    executed_at: at, executed_price: px, executed_quantity: qty, pnl: 0,
  });
  const livePosition = async (minutes) => {
    if (!metricsEngine._brokerageRulesMap) metricsEngine._brokerageRulesMap = {};
    await metricsEngine._rebuildUserCache(String(userId), 0, 0, null, {}, [], null, minutes);
    const m = metricsEngine._computeUserMetrics(String(userId));
    return m.positions.find((p) => p.instrument_token === TOKEN);
  };
  const verdict = async (minutes, o) => {
    try {
      await holdCheck(false, { _id: userId, profit_book_minutes: minutes }, TOKEN, o.orderType, o.side, o.price || 0, 'NFO-FUT', 'NFO', 'TEST', null, o.qty);
      return false;
    } catch (e) {
      if (!/Fresh Stop-Loss/.test(e.message)) throw e;
      return true;
    }
  };
  const check = async (minutes, cases) => {
    const pos = await livePosition(minutes);
    for (const c of cases) {
      metricsEngine._bidMap.set(TOKEN, c.bid);
      metricsEngine._askMap.set(TOKEN, c.ask);
      const server = await verdict(minutes, c);
      const app = predictRefused(pos, c);
      expect({ case: c, app }).toEqual({ case: c, app: server });
    }
    return pos;
  };

  test('live data: long, part old / part new — the app predicts every server verdict', async () => {
    await fill('BUY', minutesAgo(30), 10, 100);
    await fill('BUY', minutesAgo(2), 10, 106); // avg 103; 10 free, 10 locked for 8 more min
    const pos = await check(10, [
      { orderType: 'MARKET', side: 'SELL', qty: 10, bid: 110, ask: 111 }, // profit, only the old 10 → allowed
      { orderType: 'MARKET', side: 'SELL', qty: 15, bid: 110, ask: 111 }, // profit, needs new lots → refused
      { orderType: 'MARKET', side: 'SELL', qty: 20, bid: 110, ask: 111 },
      { orderType: 'MARKET', side: 'SELL', qty: 25, bid: 110, ask: 111 }, // more than held → the held part counts
      { orderType: 'MARKET', side: 'SELL', qty: 20, bid: 102, ask: 103 }, // loss → allowed
      { orderType: 'MARKET', side: 'SELL', qty: 20, bid: 103, ask: 104 }, // exactly the average = not a profit
      { orderType: 'LIMIT', side: 'SELL', price: 105, qty: 20, bid: 101, ask: 102 }, // limit in profit → refused
      { orderType: 'LIMIT', side: 'SELL', price: 102, qty: 20, bid: 110, ask: 111 }, // limit at a loss → allowed
      { orderType: 'MARKET', side: 'BUY', qty: 5, bid: 110, ask: 111 }, // adding → never held
    ]);
    expect(pos.profit_hold).toMatchObject({ minutes: 10, avg: 103, free_qty: 10 });
    expect(pos.profit_hold.lots).toHaveLength(1);
    expect(pos.profit_hold.lots[0].qty).toBe(10);
  });

  test('live data: short position — profit is the ask below the average', async () => {
    await fill('SELL', minutesAgo(3), 10, 100);
    await check(15, [
      { orderType: 'MARKET', side: 'BUY', qty: 10, bid: 94, ask: 95 }, // profit → refused
      { orderType: 'MARKET', side: 'BUY', qty: 10, bid: 104, ask: 105 }, // loss → allowed
      { orderType: 'LIMIT', side: 'BUY', price: 99, qty: 10, bid: 104, ask: 105 }, // limit in profit → refused
    ]);
  });

  test('live data: no hold time, or the time is over → no profit_hold at all (no timer)', async () => {
    await fill('BUY', minutesAgo(2), 10, 100);
    expect((await livePosition(0)).profit_hold).toBeUndefined();
    await Trade.deleteMany({});
    await fill('BUY', minutesAgo(30), 10, 100);
    expect((await livePosition(10)).profit_hold).toBeUndefined();
    metricsEngine._bidMap.set(TOKEN, 110);
    expect(await verdict(10, { orderType: 'MARKET', side: 'SELL', qty: 10 })).toBe(false);
  });
});
