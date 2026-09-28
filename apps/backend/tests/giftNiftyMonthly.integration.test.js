'use strict';

// GIFT NIFTY monthly contracts (giftNiftyContracts.js + giftNiftyFeedService
// + giftNiftySettlementService), against a throwaway `stkr_giftm_it_*` DB:
//   RUN_SETTLEMENT_INTEGRATION=1 MONGO_URI=... npx jest tests/giftNiftyMonthly.integration.test.js

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');
const axios = require('axios');

const KiteInstrument = require('../src/models/KiteInstrument');
const Master = require('../src/models/Master');
const Trade = require('../src/models/Trade');
const TradeWriteLease = require('../src/models/TradeWriteLease');
const Transaction = require('../src/models/Transaction');
const User = require('../src/models/User');
const metricsEngine = require('../src/services/metricsEngine');
const livePriceService = require('../src/services/livePriceService');
const contracts = require('../src/services/giftNiftyContracts');
const feed = require('../src/services/giftNiftyFeedService');
const { fetchAndApplyGiftNiftySettlement } = require('../src/services/giftNiftySettlementService');
const rolloverService = require('../src/services/rolloverService');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_giftm_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(120_000);
const d = (s) => new Date(`${s}T00:00:00.000Z`);
const MODELS = [KiteInstrument, Master, Trade, TradeWriteLease, Transaction, User];
const OCT = contracts.contractToken(d('2026-10-27'));
const NOV = contracts.contractToken(d('2026-11-23'));

const istStamp = (date) => {
  const p = new Date(date.getTime() + 330 * 60000);
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][p.getUTCMonth()];
  return `${String(p.getUTCDate()).padStart(2, '0')}-${mon}-${p.getUTCFullYear()} ${String(p.getUTCHours()).padStart(2, '0')}:${String(p.getUTCMinutes()).padStart(2, '0')}:${String(p.getUTCSeconds()).padStart(2, '0')}`;
};
const row = (expiry, last, bid, ask, ts = istStamp(new Date())) => ({ INSTRUMENTTYPE: 'FUTIDX', SYMBOL: 'NIFTY', EXPIRYDATE: expiry, LASTPRICE: last, BIDPRICE: bid, ASKPRICE: ask, TIMESTMP: ts });

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

describeIntegration('GIFT NIFTY monthly contracts (real MongoDB)', () => {
  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_giftm_it_')) throw new Error(`Refusing to test against ${mongoose.connection.name}`);
    for (const model of MODELS) await model.syncIndexes();
    feed.livePriceService = livePriceService;
    jest.spyOn(livePriceService, '_broadcastToClients').mockImplementation(() => {});
  });

  beforeEach(async () => {
    await Promise.all(MODELS.map((m) => m.deleteMany({})));
    resetCaches();
    await KiteInstrument.create({
      instrument_token: '291849', exchange_token: '2918499', tradingsymbol: 'GIFT NIFTY', name: 'GIFT NIFTY', raw_name: 'GIFT NIFTY',
      expiry: d('2026-09-29'), strike: 0, tick_size: 0.5, lot_size: 1, instrument_type: 'EQ', segment: 'INDICES', exchange: 'NSEIX',
    });
    feed.instrumentToken = '291849';
    feed._continuousRetired = false;
  });

  afterAll(async () => {
    try {
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_giftm_it_')) await mongoose.connection.dropDatabase();
    } finally {
      await mongoose.disconnect();
    }
  });

  test('months are created from NSE IX: nearest open, later ones closed; re-running changes nothing', async () => {
    expect(await contracts.ensureContracts([d('2026-09-29'), d('2026-10-27')])).toEqual(['GIFTNIFTY26OCTFUT']);
    expect(await contracts.ensureContracts([d('2026-10-27'), d('2026-11-23')])).toEqual(['GIFTNIFTY26NOVFUT']);
    expect(await contracts.ensureContracts([d('2026-10-27'), d('2026-11-23')])).toEqual([]);
    const oct = await KiteInstrument.findOne({ instrument_token: OCT }).lean();
    const nov = await KiteInstrument.findOne({ instrument_token: NOV }).lean();
    expect(oct).toMatchObject({ tradingsymbol: 'GIFTNIFTY26OCTFUT', name: 'GIFT NIFTY', segment: 'INDICES', exchange: 'NSEIX', instrument_type: 'FUT', enabled: true });
    expect(nov).toMatchObject({ tradingsymbol: 'GIFTNIFTY26NOVFUT', enabled: false });
    expect(await KiteInstrument.countDocuments({ exchange: 'NSEIX', instrument_type: 'FUT' })).toBe(2); // no Sep month
  });

  test("each month is priced from its own NSE IX row; stale rows are ignored", async () => {
    const stale = istStamp(new Date(Date.now() - 20 * 60000));
    const ticks = feed._tickMonthlyContracts([
      row('29-Sep-2026', 22899.5, 22899.5, 22900), // old month: stays on the continuous instrument
      row('27-Oct-2026', 22926.5, 22926, 22926.5),
      row('23-Nov-2026', 23000, 22990, 23010, stale),
    ]);
    expect(ticks.map((t) => t.instrument_token)).toEqual([OCT]);
    expect(metricsEngine._bidMap.get(OCT)).toBe(22926);
    expect(metricsEngine._askMap.get(OCT)).toBe(22926.5);
    expect(metricsEngine._bidMap.get(NOV)).toBeUndefined();
  });

  test('the continuous instrument is closed for new trades once, after Sep expiry — not before, not again', async () => {
    await feed._retireContinuousIfDue(new Date('2026-09-29T09:00:00Z'));
    expect((await KiteInstrument.findOne({ instrument_token: '291849' }).lean()).enabled).not.toBe(false);
    await feed._retireContinuousIfDue(new Date('2026-09-29T10:40:00Z'));
    const retired = await KiteInstrument.findOne({ instrument_token: '291849' }).lean();
    expect(retired.enabled).toBe(false);
    expect(retired.ban_reason).toMatch(/monthly contracts/);
    // An admin re-opens it deliberately: never closed again.
    await KiteInstrument.updateOne({ instrument_token: '291849' }, { $set: { enabled: true } });
    feed._continuousRetired = false;
    await feed._retireContinuousIfDue(new Date('2026-09-30T04:00:00Z'));
    expect((await KiteInstrument.findOne({ instrument_token: '291849' }).lean()).enabled).toBe(true);
  });

  test('weekly settlement prices each month from its own row of the NSE IX file', async () => {
    await contracts.ensureContracts([d('2026-10-27'), d('2026-11-23')]);
    const csv = [
      'DATE,INSTRUMENT TYPE,SYMBOL,EXPIRY DATE,STRIKE,OPTION TYPE,SETTLEMENT PRICE',
      '02-Oct-2026,FUTIDX,NIFTY,27-Oct-2026,0,XX,23111.5',
      '02-Oct-2026,FUTIDX,NIFTY,23-Nov-2026,0,XX,23190',
      '02-Oct-2026,FUTSTK,RELIANCE,27-Oct-2026,0,XX,1500',
    ].join('\n');
    const spy = jest.spyOn(axios, 'get').mockImplementation(async (url) => (
      url.includes('daily-settlement-prices')
        ? { data: [{ FILE_DATE: '2026-10-02', FILE_NAME: 'https://example.invalid/G_T_DSP_INDEX_02102026.csv' }] }
        : { data: csv }
    ));
    try {
      const r = await fetchAndApplyGiftNiftySettlement(new Date('2026-10-02T12:00:00Z'), { applyToLivePrices: false });
      expect(r.updated).toBe(3);
    } finally {
      spy.mockRestore();
    }
    const [oct, nov, cont] = await Promise.all([OCT, NOV, '291849'].map((t) => KiteInstrument.findOne({ instrument_token: t }).lean()));
    expect(oct).toMatchObject({ settlement_price: 23111.5, settlement_price_source: 'NSEIX_OFFICIAL_DAILY_SETTLEMENT' });
    expect(nov.settlement_price).toBe(23190);
    expect(cont.settlement_price).toBe(23111.5); // continuous keeps the near month, as before
  });

  test('rollover GIFTNIFTY26OCTFUT -> GIFTNIFTY26NOVFUT at each month\'s own bid/ask; continuous still rejected', async () => {
    await contracts.ensureContracts([d('2026-10-27'), d('2026-11-23')]);
    await KiteInstrument.updateOne({ instrument_token: NOV }, { $set: { enabled: true } }); // Nov opened (Mon 26 Oct)
    const serverId = new mongoose.Types.ObjectId();
    const master = await Master.create({ name: 'G', username: 'g_m', password: 'x', credits: 1e6, equity: 1e6, server_id: serverId, admin_id: new mongoose.Types.ObjectId() });
    const user = await User.create({
      name: 'G', username: 'g_u', password: 'x', credits: 1e6, equity: 1e6, server_id: serverId, master_id: master._id,
      wallet: { NSE: 0, MCX: 0, GLOBAL: 1e6 }, exchanges_allowed: [{ exchange_name: 'INDICES', turnover: true, lot: false, group_name: 'GOLDMIN' }],
    });
    for (const [token, sym] of [[OCT, 'GIFTNIFTY26OCTFUT'], ['291849', 'GIFT NIFTY']]) {
      await Trade.create({ user_id: user._id, master_id: master._id, instrument_token: token, tradingsymbol: sym, exchange: 'NSEIX',
        transaction_type: 'BUY', quantity: 2, price: 22800, order_type: 'MARKET', status: 'completed',
        executed_at: new Date('2026-10-20T06:00:00Z'), executed_price: 22800, executed_quantity: 2, pnl: 0 });
    }
    feed._tickMonthlyContracts([row('27-Oct-2026', 22926.5, 22926, 22927), row('23-Nov-2026', 23005, 23000, 23010)]);
    metricsEngine._ltpMap.set('291849', 22900);

    const { rolled_over, errors } = await rolloverService.rolloverPositions({ targetUserId: user._id.toString(), tokens: [OCT, '291849'], actor: { isAdmin: false, masterId: null } });
    expect(rolled_over).toHaveLength(1);
    expect(rolled_over[0]).toMatchObject({ old: { tradingsymbol: 'GIFTNIFTY26OCTFUT', price: 22926 }, new: { tradingsymbol: 'GIFTNIFTY26NOVFUT', price: 23010 }, qty: 2 });
    expect(errors).toEqual([expect.objectContaining({ token: '291849', message: expect.stringMatching(/continuous contract/) })]);
  });
});
