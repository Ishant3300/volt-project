'use strict';

// Real-MongoDB (transactions) test of the contract-expiry actions: OPEN
// enables the next contract; CUT captures the closing bid/ask, waits for an
// admin confirm, then closes every position (long at bid, short at ask) and
// disables the contract; an unconfirmed cut expires untouched; the 3:46 PM
// expiry safety net skips GLOBAL. Runs in a throwaway database only:
//   RUN_SETTLEMENT_INTEGRATION=1 MONGO_URI=... npx jest tests/expiryActions.integration.test.js

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');

const ExpiryAction = require('../src/models/ExpiryAction');
const KiteInstrument = require('../src/models/KiteInstrument');
const Master = require('../src/models/Master');
const Trade = require('../src/models/Trade');
const TradeWriteLease = require('../src/models/TradeWriteLease');
const Transaction = require('../src/models/Transaction');
const User = require('../src/models/User');
const Watchlist = require('../src/models/Watchlist');
const metricsEngine = require('../src/services/metricsEngine');
const livePriceService = require('../src/services/livePriceService');
const cronService = require('../src/services/cronService');
const expiryActionService = require('../src/services/expiryActionService');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_expiry_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(120_000);

const d = (s) => new Date(`${s}T00:00:00.000Z`);

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

async function seed() {
  const serverId = new mongoose.Types.ObjectId();
  const master = await Master.create({
    name: 'Expiry IT master', username: 'exp_it_master', password: 'x',
    credits: 1_000_000, equity: 1_000_000, server_id: serverId, admin_id: new mongoose.Types.ObjectId(), exchanges_allowed: ['MCX-FUT'],
  });
  const mkUser = (i, wallet) => ({
    name: `Expiry IT ${i}`, username: `exp_it_user_${i}`, password: 'x', credits: 100_000, equity: 100_000,
    server_id: serverId, master_id: master._id, wallet,
    exchanges_allowed: [{ exchange_name: 'MCX-FUT', turnover: true, lot: false, group_name: 'GOLDMIN' }],
  });
  const [longUser, shortUser] = await User.create([
    mkUser(1, { NSE: 0, MCX: 100_000 - 2 * 100, GLOBAL: 0 }),
    mkUser(2, { NSE: 0, MCX: 100_000 - 1 * 110, GLOBAL: 0 }),
  ]);
  const inst = (token, expiry, enabled, extra = {}) => ({
    instrument_token: token, exchange_token: `${token}9`, tradingsymbol: `COPPER${token}FUT`, name: 'COPPER',
    raw_name: 'COPPER', last_price: 119, expiry: d(expiry), strike: 0, tick_size: 0.05, lot_size: 1,
    instrument_type: 'FUT', segment: 'MCX-FUT', exchange: 'MCX', enabled, ...extra,
  });
  await KiteInstrument.create([inst('9101', '2026-10-30', true), inst('9102', '2026-11-30', false)]);
  const trade = (user, side, qty, price) => ({
    user_id: user._id, master_id: master._id, instrument_token: '9101', tradingsymbol: 'COPPER9101FUT', exchange: 'MCX',
    transaction_type: side, quantity: qty, price, order_type: 'MARKET', status: 'completed',
    executed_at: new Date('2026-10-20T06:00:00Z'), executed_price: price, executed_quantity: qty, pnl: 0,
  });
  await Trade.create([trade(longUser, 'BUY', 2, 100), trade(shortUser, 'SELL', 1, 110)]);
  // Last quotation at the 11:30 PM close.
  metricsEngine._bidMap.set('9101', 120);
  metricsEngine._askMap.set('9101', 122);
  metricsEngine._ltpMap.set('9101', 121);
  return { longUser, shortUser };
}

const baseAction = (kind, executeAt, extra = {}) => ({
  key: `MCX_BASE|${kind}|2026-10-30`, group_key: 'MCX_BASE', group_label: 'Base metals', exchange_label: 'MCX',
  kind, segments: ['MCX-FUT'], names: ['COPPER'], current_expiry: d('2026-10-30'),
  targets: kind === 'OPEN' ? [{ name: 'COPPER', expiry: d('2026-11-30') }] : [],
  action_date: '2026-10-23', close_time: kind === 'CUT' ? '23:30' : null, execute_at: new Date(executeAt), ...extra,
});

describeIntegration('contract expiry actions (real MongoDB)', () => {
  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_expiry_it_')) throw new Error(`Refusing to test against ${mongoose.connection.name}`);
    for (const model of [ExpiryAction, KiteInstrument, Master, Trade, TradeWriteLease, Transaction, User, Watchlist]) await model.syncIndexes();
  });

  beforeEach(async () => {
    await Promise.all([ExpiryAction, KiteInstrument, Master, Trade, TradeWriteLease, Transaction, User, Watchlist].map((m) => m.deleteMany({})));
    resetCaches();
  });

  afterAll(async () => {
    try {
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_expiry_it_')) {
        await mongoose.connection.dropDatabase();
      }
    } finally {
      await mongoose.disconnect();
    }
  });

  test('OPEN enables the next contract at its time, automatically', async () => {
    await seed();
    const open = await ExpiryAction.create(baseAction('OPEN', '2026-10-22T02:30:00Z'));

    await expiryActionService.runDue(new Date('2026-10-22T02:29:00Z'));
    expect((await KiteInstrument.findOne({ instrument_token: '9102' }).lean()).enabled).toBe(false);

    await expiryActionService.runDue(new Date('2026-10-22T02:31:00Z'));
    expect((await KiteInstrument.findOne({ instrument_token: '9102' }).lean()).enabled).toBe(true);
    expect(await ExpiryAction.findById(open._id).lean()).toMatchObject({ status: 'done', result: { contracts: 1 } });
  });

  test('CUT snapshots the close, waits for confirm, then closes at bid/ask and disables the contract', async () => {
    const { longUser, shortUser } = await seed();
    const cut = await ExpiryAction.create(baseAction('CUT', '2026-10-23T18:01:00Z'));
    const [oldInst, nextInst] = await Promise.all([KiteInstrument.findOne({ instrument_token: '9101' }).lean(), KiteInstrument.findOne({ instrument_token: '9102' }).lean()]);
    const watch = (owner, inst, order) => ({ kite_instrument_id: inst._id, instrument_token: inst.instrument_token, order, owner_id: owner._id, owner_type: 'User' });
    // longUser watches only the old contract; shortUser already watches both.
    await Watchlist.create([watch(longUser, oldInst, 3), watch(shortUser, oldInst, 1), watch(shortUser, nextInst, 2)]);

    // Just after the close: snapshot taken, but nothing closes without a confirm.
    await expiryActionService.runDue(new Date('2026-10-23T18:02:00Z'));
    let a = await ExpiryAction.findById(cut._id).lean();
    expect(a.status).toBe('planned');
    expect(a.snapshot.prices).toEqual([{ token: '9101', symbol: 'COPPER9101FUT', bid: 120, ask: 122, ltp: 121 }]);
    expect(await Trade.countDocuments({ trade_type: 'admin_square_off' })).toBe(0);

    // Quotes move after the snapshot — the cut must still use the closing snapshot.
    metricsEngine._bidMap.set('9101', 50);
    metricsEngine._askMap.set('9101', 60);

    await expiryActionService.transition(cut._id, 'confirm', null, new Date('2026-10-23T18:05:00Z'));
    await expiryActionService.runDue(new Date('2026-10-23T18:10:00Z'));

    a = await ExpiryAction.findById(cut._id).lean();
    expect(a).toMatchObject({ status: 'done', result: { open_positions: 2, positions_closed: 2, contracts: 1 } });
    const closes = await Trade.find({ trade_type: 'admin_square_off' }).lean();
    const byUser = Object.fromEntries(closes.map((t) => [t.user_id.toString(), t]));
    expect(byUser[longUser._id]).toMatchObject({ transaction_type: 'SELL', executed_quantity: 2, executed_price: 120, pnl: 40, placed_by: 'ADMIN' });
    expect(byUser[shortUser._id]).toMatchObject({ transaction_type: 'BUY', executed_quantity: 1, executed_price: 122, pnl: -12 });
    expect(await Transaction.countDocuments({ 'metadata.reason': 'EXPIRY_CUT' })).toBe(2);
    // Entry notional released back to the MCX wallet; P&L booked to equity.
    expect((await User.findById(longUser._id).lean()).wallet.MCX).toBe(100_000);
    expect((await User.findById(longUser._id).lean()).equity).toBe(100_040);
    expect((await KiteInstrument.findOne({ instrument_token: '9101' }).lean()).enabled).toBe(false);

    // Watchlists: old contract moved to the next one in place, or dropped if already watched.
    expect(a.result).toMatchObject({ watchlist_swapped: 1, watchlist_removed: 1 });
    expect(await Watchlist.findOne({ owner_id: longUser._id, deleted_at: null }).lean()).toMatchObject({ instrument_token: '9102', order: 3 });
    expect((await Watchlist.find({ owner_id: shortUser._id, deleted_at: null }).lean()).map((w) => w.instrument_token)).toEqual(['9102']);
    expect(await Watchlist.countDocuments({ instrument_token: '9101', deleted_at: null })).toBe(0);

    // Re-running is harmless: nothing left open, no second close.
    await expiryActionService.transition(cut._id, 'pause', null).catch(() => {});
    await expiryActionService.runDue(new Date('2026-10-23T18:20:00Z'));
    expect(await Trade.countDocuments({ trade_type: 'admin_square_off' })).toBe(2);
  });

  test('an unconfirmed CUT is marked missed after the window and closes nothing', async () => {
    await seed();
    const cut = await ExpiryAction.create(baseAction('CUT', '2026-10-23T18:01:00Z'));
    await expiryActionService.runDue(new Date('2026-10-24T03:30:00Z')); // 9.5h later
    const a = await ExpiryAction.findById(cut._id).lean();
    expect(a.status).toBe('failed');
    expect(a.error).toMatch(/Not confirmed/);
    await expect(expiryActionService.transition(cut._id, 'confirm', null, new Date('2026-10-24T03:30:00Z'))).rejects.toMatchObject({ status: 409 });
    expect(await Trade.countDocuments({ trade_type: 'admin_square_off' })).toBe(0);
    expect((await KiteInstrument.findOne({ instrument_token: '9101' }).lean()).enabled).toBe(true);
  });

  test('expiry-day safety net closes at bid/ask and its 3:46 PM run skips GLOBAL', async () => {
    const { longUser } = await seed();
    const now = new Date('2026-10-30T10:16:00Z');
    await KiteInstrument.create({
      instrument_token: '9201', exchange_token: '92019', tradingsymbol: 'ES26DECFUT', name: 'S&P 500', raw_name: 'S&P 500',
      last_price: 5000, expiry: d('2026-10-30'), strike: 0, tick_size: 0.25, lot_size: 1,
      instrument_type: 'FUT', segment: 'GLOBAL', exchange: 'GLOBAL',
    });
    await Trade.create({
      user_id: longUser._id, master_id: longUser.master_id, instrument_token: '9201', tradingsymbol: 'ES26DECFUT', exchange: 'GLOBAL',
      transaction_type: 'BUY', quantity: 1, price: 4900, order_type: 'MARKET', status: 'completed',
      executed_at: new Date('2026-10-20T06:00:00Z'), executed_price: 4900, executed_quantity: 1, pnl: 0,
    });

    await cronService.autoSquareOffExpiredPositions({ now, skipSegments: ['GLOBAL', 'COMEX-FUT'] });

    const closes = await Trade.find({ trade_type: 'margin_square_off' }).lean();
    expect(closes.map((t) => t.instrument_token).sort()).toEqual(['9101', '9101']);
    const longClose = closes.find((t) => t.user_id.toString() === longUser._id.toString());
    expect(longClose).toMatchObject({ transaction_type: 'SELL', executed_price: 120 }); // bid, not LTP 121
    expect(await Trade.countDocuments({ instrument_token: '9201' })).toBe(1); // GLOBAL untouched
  });

  test('a contract loaded after the cutoff starts closed until its open day — once only', async () => {
    const { NEW_CONTRACTS_CLOSED_FROM } = require('../src/config/expiryRules');
    const idAt = (ms) => mongoose.Types.ObjectId.createFromTime(Math.floor((NEW_CONTRACTS_CLOSED_FROM.getTime() + ms) / 1000));
    const inst = (id, token, name, expiry) => ({
      _id: id, instrument_token: token, exchange_token: `${token}9`, tradingsymbol: `${name}${token}`, name, raw_name: name,
      expiry: d(expiry), strike: 0, tick_size: 1, lot_size: 1, instrument_type: 'FUT', segment: 'MCX-FUT', exchange: 'MCX', enabled: true,
    });
    await KiteInstrument.create([
      inst(idAt(3_600_000), '9301', 'COPPER', '2026-11-30'), // loaded after the cutoff
      inst(idAt(-3_600_000), '9302', 'ZINC', '2026-11-30'), // already existed — admin's choice stands
    ]);
    const open = await ExpiryAction.create(baseAction('OPEN', '2026-10-22T02:30:00Z', {
      names: ['COPPER', 'ZINC'], targets: [{ name: 'COPPER', expiry: d('2026-11-30') }, { name: 'ZINC', expiry: d('2026-11-30') }],
    }));
    const now = new Date('2026-10-01T00:00:00Z');
    const { closeNewTargetsUntilOpen } = expiryActionService._private;

    await closeNewTargetsUntilOpen(now);
    expect(await KiteInstrument.findOne({ instrument_token: '9301' }).lean()).toMatchObject({ enabled: false, ban_reason: 'Opens for trading on 2026-10-23' });
    expect((await KiteInstrument.findOne({ instrument_token: '9302' }).lean()).enabled).toBe(true);
    expect((await ExpiryAction.findById(open._id).lean()).closed_targets.sort()).toEqual(['COPPER|2026-11-30', 'ZINC|2026-11-30']);

    // An admin opens it early by hand — the next refresh must not close it again.
    await KiteInstrument.updateOne({ instrument_token: '9301' }, { $set: { enabled: true } });
    await closeNewTargetsUntilOpen(now);
    expect((await KiteInstrument.findOne({ instrument_token: '9301' }).lean()).enabled).toBe(true);
  });

  test('announcement text follows the circulated format', async () => {
    await ExpiryAction.create([
      baseAction('OPEN', '2026-10-22T02:30:00Z', { action_date: '2026-10-22', names: ['COPPER', 'ZINC'], targets: [{ name: 'COPPER', expiry: d('2026-11-30') }, { name: 'ZINC', expiry: d('2026-11-30') }] }),
      baseAction('CUT', '2026-10-23T18:01:00Z'),
    ]);
    const { message } = await expiryActionService.buildAnnouncement('2026-10-22');
    expect(message).toBe([
      'NEW CONTRACT Open 📢', '', 'MCX - ', '', 'COPPER', 'ZINC', '',
      'Old Contract settlement: 23-OCT-FRIDAY at last Quotation', ' ( 11.30 P.M. )',
    ].join('\n'));
  });
});
