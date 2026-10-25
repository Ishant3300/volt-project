'use strict';

// Real-MongoDB (transactions) test of services/rolloverService.js.
//   RUN_SETTLEMENT_INTEGRATION=1 MONGO_URI=... npx jest tests/rollover.integration.test.js
// Runs only in a throwaway `stkr_rollover_it_*` database, dropped afterwards.

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');

const BrokerageSettings = require('../src/models/BrokerageSettings');
const ExpiryAction = require('../src/models/ExpiryAction');
const KiteInstrument = require('../src/models/KiteInstrument');
const Master = require('../src/models/Master');
const Trade = require('../src/models/Trade');
const TradeWriteLease = require('../src/models/TradeWriteLease');
const Transaction = require('../src/models/Transaction');
const User = require('../src/models/User');
const metricsEngine = require('../src/services/metricsEngine');
const livePriceService = require('../src/services/livePriceService');
const rolloverService = require('../src/services/rolloverService');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_rollover_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(120_000);
const d = (s) => new Date(`${s}T00:00:00.000Z`);
const MODELS = [BrokerageSettings, ExpiryAction, KiteInstrument, Master, Trade, TradeWriteLease, Transaction, User];

function resetCaches() {
  metricsEngine._userCache.clear();
  metricsEngine._tokenToUsers.clear();
  metricsEngine._metricsCache.clear();
  metricsEngine._ltpMap.clear();
  metricsEngine._bidMap.clear();
  metricsEngine._askMap.clear();
  metricsEngine._brokerageRules = [];
  metricsEngine._kiteMap = {};
  metricsEngine.livePriceService = livePriceService;
  metricsEngine._initialized = true;
}

const quote = (token, bid, ask) => {
  metricsEngine._bidMap.set(token, bid);
  metricsEngine._askMap.set(token, ask);
  metricsEngine._ltpMap.set(token, (bid + ask) / 2);
};

async function seed({ nextEnabled = true } = {}) {
  const serverId = new mongoose.Types.ObjectId();
  const master = await Master.create({
    name: 'Roll IT master', username: 'roll_it_master', password: 'x', credits: 1e6, equity: 1e6,
    server_id: serverId, admin_id: new mongoose.Types.ObjectId(), exchanges_allowed: ['MCX-FUT'],
  });
  const user = await User.create({
    name: 'Roll IT user', username: 'roll_it_user', password: 'x', credits: 100_000, equity: 100_000,
    server_id: serverId, master_id: master._id, wallet: { NSE: 0, MCX: 100_000 - 2 * 100, GLOBAL: 0 },
    exchanges_allowed: [{ exchange_name: 'MCX-FUT', turnover: true, lot: false, group_name: 'GOLDMIN' }],
  });
  const inst = (token, expiry, enabled) => ({
    instrument_token: token, exchange_token: `${token}9`, tradingsymbol: `COPPER${expiry.slice(5, 7)}FUT`, name: 'COPPER',
    raw_name: 'COPPER', expiry: d(expiry), strike: 0, tick_size: 0.05, lot_size: 1,
    instrument_type: 'FUT', segment: 'MCX-FUT', exchange: 'MCX', enabled,
  });
  await KiteInstrument.create([inst('8101', '2026-10-30', true), inst('8102', '2026-11-30', nextEnabled)]);
  // 0.1% turnover brokerage for this client on COPPER.
  await BrokerageSettings.create({ user_id: user._id, exchange_name: 'MCX-FUT', script_name: 'COPPER', type: 'TURNOVER WISE', brk_value: 10 });
  await Trade.create({
    user_id: user._id, master_id: master._id, instrument_token: '8101', tradingsymbol: 'COPPER10FUT', exchange: 'MCX',
    transaction_type: 'BUY', quantity: 2, price: 100, order_type: 'MARKET', status: 'completed',
    executed_at: new Date('2026-10-20T06:00:00Z'), executed_price: 100, executed_quantity: 2, pnl: 0,
  });
  quote('8101', 120, 121);
  quote('8102', 125, 126);
  return { master, user };
}

const run = (user, tokens = ['8101']) => rolloverService.rolloverPositions({
  targetUserId: user._id.toString(), tokens, actor: { isAdmin: false, masterId: null },
});

describeIntegration('rollover (real MongoDB)', () => {
  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_rollover_it_')) throw new Error(`Refusing to test against ${mongoose.connection.name}`);
    for (const model of MODELS) await model.syncIndexes();
  });

  beforeEach(async () => {
    await Promise.all(MODELS.map((m) => m.deleteMany({})));
    resetCaches();
  });

  afterAll(async () => {
    try {
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_rollover_it_')) {
        await mongoose.connection.dropDatabase();
      }
    } finally {
      await mongoose.disconnect();
    }
  });

  test('closes at the bid, reopens at the ask, with brokerage, wallet and ledger right', async () => {
    const { user } = await seed();
    const { rolled_over, errors } = await run(user);
    expect(errors).toEqual([]);
    expect(rolled_over).toHaveLength(1);

    const legs = await Trade.find({ rollover_group_id: { $ne: null } }).sort({ executed_at: 1 }).lean();
    expect(legs.map((t) => [t.instrument_token, t.transaction_type, t.executed_quantity, t.executed_price])).toEqual([
      ['8101', 'SELL', 2, 120],
      ['8102', 'BUY', 2, 126],
    ]);
    expect(legs[0].pnl).toBe(40);
    expect(legs[0].brokerage).toBeCloseTo(0.24, 6); // 120*2 * 0.1%
    expect(legs[1].brokerage).toBeCloseTo(0.252, 6); // 126*2 * 0.1%
    expect(String(legs[0].rollover_group_id)).toBe(String(legs[1].rollover_group_id));

    const after = await User.findById(user._id).lean();
    expect(after.wallet.MCX).toBeCloseTo(100_000 - 2 * 126, 6); // entry 200 released, 252 blocked
    expect(after.equity).toBeCloseTo(100_000 + 40 - 0.24 - 0.252, 6);
    const txs = await Transaction.find({}).sort({ transactionId: 1 }).lean();
    expect(txs.map((t) => t.metadata.rollover_leg).sort()).toEqual(['close', 'open']);
  });

  test('next contract not open yet: rejected with the scheduled open day, nothing written', async () => {
    const { user } = await seed({ nextEnabled: false });
    await ExpiryAction.create({
      key: 'MCX_BASE|OPEN|2026-10-30', group_key: 'MCX_BASE', group_label: 'Base metals', exchange_label: 'MCX', kind: 'OPEN',
      segments: ['MCX-FUT'], names: ['COPPER'], current_expiry: d('2026-10-30'), targets: [{ name: 'COPPER', expiry: d('2026-11-30') }],
      action_date: '2026-10-22', execute_at: new Date('2026-10-22T02:30:00Z'),
    });
    const { rolled_over, errors } = await run(user);
    expect(rolled_over).toEqual([]);
    expect(errors).toEqual([{ token: '8101', tradingsymbol: 'COPPER10FUT', message: expect.stringMatching(/COPPER10FUT: Rollover to COPPER11FUT opens on Thu, 22 Oct/) }]);
    expect(await Trade.countDocuments({})).toBe(1);
  });

  test('GIFT NIFTY, unknown and flat positions are rejected clearly', async () => {
    const { user } = await seed();
    await KiteInstrument.create({
      instrument_token: '291849', exchange_token: '2918499', tradingsymbol: 'GIFT NIFTY', name: 'GIFT NIFTY', raw_name: 'GIFT NIFTY',
      expiry: d('2026-10-27'), strike: 0, tick_size: 0.5, lot_size: 1, instrument_type: 'EQ', segment: 'INDICES', exchange: 'NSEIX',
    });
    await Trade.create({
      user_id: user._id, master_id: user.master_id, instrument_token: '291849', tradingsymbol: 'GIFT NIFTY', exchange: 'NSEIX',
      transaction_type: 'BUY', quantity: 1, price: 23000, order_type: 'MARKET', status: 'completed',
      executed_at: new Date('2026-10-20T06:00:00Z'), executed_price: 23000, executed_quantity: 1, pnl: 0,
    });
    const { errors } = await run(user, ['291849', '8102', '999999']);
    const byToken = Object.fromEntries(errors.map((e) => [e.token, e.message]));
    expect(byToken['291849']).toMatch(/continuous contract/);
    expect(byToken['8102']).toMatch(/No open position/);
    expect(byToken['999999']).toMatch(/Instrument not found/);
  });

  test('no live price for the next contract: rejected and put on the feed', async () => {
    const { user } = await seed();
    metricsEngine._bidMap.delete('8102');
    metricsEngine._askMap.delete('8102');
    metricsEngine._ltpMap.delete('8102');
    const spy = jest.spyOn(livePriceService, 'ensureSubscribed').mockReturnValue(1);
    try {
      const { rolled_over, errors } = await run(user);
      expect(rolled_over).toEqual([]);
      expect(errors[0].message).toMatch(/No live price for COPPER11FUT yet/);
      expect(spy).toHaveBeenCalledWith(['8102']);
    } finally {
      spy.mockRestore();
    }
  });

  test('a double tap (two requests at once) rolls the position only once', async () => {
    const { user } = await seed();
    const [a, b] = await Promise.all([run(user), run(user)]);
    expect(a.rolled_over.length + b.rolled_over.length).toBe(1);
    expect([...a.errors, ...b.errors].map((e) => e.message)).toEqual([expect.stringMatching(/No open position/)]);
    expect(await Trade.countDocuments({ rollover_group_id: { $ne: null } })).toBe(2);
    expect((await User.findById(user._id).lean()).wallet.MCX).toBeCloseTo(100_000 - 2 * 126, 6);
  });

  async function addZincPosition(user, { walletMcx } = {}) {
    await KiteInstrument.create([
      { instrument_token: '8201', exchange_token: '82019', tradingsymbol: 'ZINC10FUT', name: 'ZINC', raw_name: 'ZINC', expiry: d('2026-10-30'), strike: 0, tick_size: 0.05, lot_size: 1, instrument_type: 'FUT', segment: 'MCX-FUT', exchange: 'MCX', enabled: true },
      { instrument_token: '8202', exchange_token: '82029', tradingsymbol: 'ZINC11FUT', name: 'ZINC', raw_name: 'ZINC', expiry: d('2026-11-30'), strike: 0, tick_size: 0.05, lot_size: 1, instrument_type: 'FUT', segment: 'MCX-FUT', exchange: 'MCX', enabled: true },
    ]);
    await Trade.create({
      user_id: user._id, master_id: user.master_id, instrument_token: '8201', tradingsymbol: 'ZINC10FUT', exchange: 'MCX',
      transaction_type: 'SELL', quantity: 10, price: 300, order_type: 'MARKET', status: 'completed',
      executed_at: new Date('2026-10-21T06:00:00Z'), executed_price: 300, executed_quantity: 10, pnl: 0,
    });
    quote('8201', 290, 291);
    quote('8202', 295, 296);
    if (walletMcx !== undefined) await User.updateOne({ _id: user._id }, { $set: { 'wallet.MCX': walletMcx } });
  }

  test('several positions roll together in one transaction with the same results', async () => {
    const { user } = await seed();
    await addZincPosition(user, { walletMcx: 100_000 - 200 - 3000 });
    const { rolled_over, errors } = await run(user, ['8101', '8201']);
    expect(errors).toEqual([]);
    expect(rolled_over.map((r) => r.new.tradingsymbol).sort()).toEqual(['COPPER11FUT', 'ZINC11FUT']);
    const zinc = await Trade.find({ instrument_token: { $in: ['8201', '8202'] }, rollover_group_id: { $ne: null } }).sort({ executed_at: 1 }).lean();
    expect(zinc.map((t) => [t.transaction_type, t.executed_price])).toEqual([['BUY', 291], ['SELL', 295]]); // short: close at ask, reopen at bid
    expect(zinc[0].pnl).toBe(90); // (300 - 291) * 10
    const after = await User.findById(user._id).lean();
    // released 200 + 3000, blocked 2*126 + 10*295
    expect(after.wallet.MCX).toBeCloseTo(100_000 - 200 - 3000 + 200 + 3000 - 252 - 2950, 6);
    expect(await Transaction.countDocuments({})).toBe(4);
  });

  test('wallet covers only one reopen: batch falls back, one rolls, the other gets its own message', async () => {
    const { user } = await seed();
    // Free MCX balance 0 after both entries are released it has 3200; reopening both needs 3202.
    await addZincPosition(user, { walletMcx: 0 });
    const { rolled_over, errors } = await run(user, ['8101', '8201']);
    expect(rolled_over).toHaveLength(1);
    expect(errors).toHaveLength(1);
    expect(errors[0].message).toMatch(/Insufficient MCX wallet balance to reopen on/);
    const w = (await User.findById(user._id).lean()).wallet.MCX;
    expect(w).toBeGreaterThanOrEqual(0);
  });

  test('overloaded: waits for a free slot, then rolls (never "busy", 25 Oct 2026)', async () => {
    const { user } = await seed();
    const { gate, MAX_ACTIVE, leaveGate } = rolloverService._private;
    const saved = gate.active;
    gate.active = MAX_ACTIVE;
    const pending = run(user);
    await new Promise((r) => setTimeout(r, 200));
    expect(await Trade.countDocuments({ rollover_group_id: { $ne: null } })).toBe(0); // still waiting
    leaveGate(); // a slot frees up
    const { rolled_over, errors } = await pending;
    gate.active = saved;
    expect(errors).toEqual([]);
    expect(rolled_over).toHaveLength(1);
  });
});
