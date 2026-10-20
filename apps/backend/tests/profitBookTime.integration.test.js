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
  test('an account without the field gets the old universal 10', () => {
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
});
