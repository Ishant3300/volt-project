'use strict';

/**
 * Rollover load test — simulates expiry day: CLIENTS users, each holding
 * POSITIONS open futures positions (each on its own contract with an opened
 * next contract) and a realistic ~600-row brokerage table, all pressing
 * Rollover at once (each request goes through rolloverService, admission
 * gate included). Runs ONLY in a throwaway `stkr_rollload_*` database,
 * dropped at the end.
 *
 *   CLIENTS=300 POSITIONS=10 node scripts/loadtest/rolloverLoad.js
 */
require('dotenv').config();
const mongoose = require('mongoose');

const CLIENTS = Number(process.env.CLIENTS) || 200;
const POSITIONS = Number(process.env.POSITIONS) || 10;
const RULES_PER_USER = Number(process.env.RULES_PER_USER) || 600;
const ARRIVAL_MS = Number(process.env.ARRIVAL_MS) || 0; // spread request starts over this window
const dbName = `stkr_rollload_${Date.now().toString(36)}`;

(async () => {
  await mongoose.connect(process.env.MONGO_URI, { dbName, autoIndex: false, autoCreate: true });
  if (!mongoose.connection.name.startsWith('stkr_rollload_')) throw new Error('unsafe db');
  const models = ['BrokerageSettings', 'KiteInstrument', 'Master', 'Trade', 'TradeWriteLease', 'Transaction', 'User', 'ScriptQuantity', 'ExpiryAction', 'SettlementFence', 'SettlementRun']
    .map((m) => require(`../../src/models/${m}`));
  for (const m of models) await m.syncIndexes();
  const [BrokerageSettings, KiteInstrument, Master, Trade, , , User] = models;
  const metricsEngine = require('../../src/services/metricsEngine');
  const livePriceService = require('../../src/services/livePriceService');
  metricsEngine.livePriceService = livePriceService;
  metricsEngine._initialized = true;
  livePriceService.broadcastToUser = () => {};
  // Phase timing: wrap the expensive-looking calls before rolloverService binds them.
  const timings = {};
  const timed = (obj, name, label) => {
    const orig = obj[name].bind(obj);
    obj[name] = async (...a) => { const t = Date.now(); try { return await orig(...a); } finally { (timings[label] ||= []).push(Date.now() - t); } };
  };
  const fence = require('../../src/services/tradeWriteFenceService');
  timed(fence, 'beginTradeWrite', 'beginTradeWrite');
  timed(metricsEngine, 'onTradeExecuted', 'onTradeExecuted');
  const walletService = require('../../src/services/walletService');
  timed(walletService, 'release', 'wallet.release');
  timed(walletService, 'block', 'wallet.block');
  const origStart = mongoose.startSession.bind(mongoose);
  mongoose.startSession = async (...a) => {
    const sess = await origStart(...a);
    const wt = sess.withTransaction.bind(sess);
    sess.withTransaction = async (fn, o2) => { const t = Date.now(); try { return await wt(fn, o2); } finally { (timings.transaction ||= []).push(Date.now() - t); } };
    return sess;
  };
  const rolloverService = require('../../src/services/rolloverService');

  try {
    const t0 = Date.now();
    // Instruments: POSITIONS contracts, each with an opened next contract.
    const inst = [];
    for (let i = 0; i < POSITIONS; i++) {
      for (const [n, exp] of [[0, '2026-10-30'], [1, '2026-11-30']]) {
        const token = String(700000 + i * 2 + n);
        inst.push({ instrument_token: token, exchange_token: `${token}9`, tradingsymbol: `S${i}${n ? 'NOV' : 'OCT'}FUT`, name: `S${i}`, raw_name: `S${i}`,
          expiry: new Date(`${exp}T00:00:00Z`), strike: 0, tick_size: 0.05, lot_size: 1, instrument_type: 'FUT', segment: 'MCX-FUT', exchange: 'MCX', enabled: true });
        metricsEngine._bidMap.set(token, 100 + n * 5);
        metricsEngine._askMap.set(token, 101 + n * 5);
        metricsEngine._ltpMap.set(token, 100.5 + n * 5);
      }
    }
    await KiteInstrument.insertMany(inst);
    const serverId = new mongoose.Types.ObjectId();
    const master = await Master.create({ name: 'LT master', username: 'lt_master', password: 'x', credits: 1e12, equity: 1e12, server_id: serverId, admin_id: new mongoose.Types.ObjectId(), exchanges_allowed: ['MCX-FUT'] });

    const users = await User.insertMany(Array.from({ length: CLIENTS }, (_, u) => ({
      name: `LT ${u}`, username: `lt_user_${u}`, password: 'x', credits: 1e9, equity: 1e9, server_id: serverId, master_id: master._id,
      wallet: { NSE: 0, MCX: 1e9, GLOBAL: 0 }, exchanges_allowed: [{ exchange_name: 'MCX-FUT', turnover: true, lot: false, group_name: 'GOLDMIN' }],
    })));
    const rules = [];
    const trades = [];
    for (const u of users) {
      for (let r = 0; r < RULES_PER_USER; r++) rules.push({ user_id: u._id, exchange_name: 'MCX-FUT', script_name: r < POSITIONS ? `S${r}` : `X${r}`, type: 'TURNOVER WISE', brk_value: 10 });
      for (let i = 0; i < POSITIONS; i++) {
        trades.push({ user_id: u._id, master_id: master._id, instrument_token: String(700000 + i * 2), tradingsymbol: `S${i}OCTFUT`, exchange: 'MCX',
          transaction_type: 'BUY', quantity: 5, price: 90, order_type: 'MARKET', status: 'completed', executed_at: new Date('2026-10-20T06:00:00Z'), executed_price: 90, executed_quantity: 5, pnl: 0 });
      }
    }
    for (let i = 0; i < rules.length; i += 20000) await BrokerageSettings.insertMany(rules.slice(i, i + 20000), { ordered: false });
    for (let i = 0; i < trades.length; i += 20000) await Trade.insertMany(trades.slice(i, i + 20000), { ordered: false });
    console.log(`seeded ${CLIENTS} clients × ${POSITIONS} positions, ${rules.length} brokerage rows in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

    const tokens = Array.from({ length: POSITIONS }, (_, i) => String(700000 + i * 2));
    const latencies = [];
    let rolled = 0; let busy = 0; let otherErr = 0;
    const cpu0 = process.cpuUsage();
    const start = Date.now();
    await Promise.all(users.map(async (u, idx) => {
      if (ARRIVAL_MS) await new Promise((r) => setTimeout(r, (idx / CLIENTS) * ARRIVAL_MS));
      const s = Date.now();
      try {
        const r = await rolloverService.rolloverPositions({ targetUserId: u._id.toString(), tokens, actor: { isAdmin: false, masterId: null } });
        rolled += r.rolled_over.length;
        otherErr += r.errors.length;
        if (r.errors.length && otherErr <= 3) console.log('error sample:', r.errors[0].message);
      } catch (e) {
        if (e.code === 'ROLLOVER_BUSY') busy++; else { otherErr++; if (otherErr <= 3) console.log('request error:', e.message); }
      }
      latencies.push(Date.now() - s);
    }));
    const secs = (Date.now() - start) / 1000;
    const cpu = process.cpuUsage(cpu0);
    latencies.sort((a, b) => a - b);
    const pct = (p) => latencies[Math.min(latencies.length - 1, Math.floor(latencies.length * p))];
    console.log(`requests ${CLIENTS} (arrival over ${ARRIVAL_MS}ms): rolled ${rolled} positions (${rolled * 2} trades), busy-rejected requests ${busy}, other errors ${otherErr}`);
    console.log(`wall ${secs.toFixed(1)}s → ${(rolled / secs).toFixed(1)} rollovers/s = ${(rolled * 2 / secs).toFixed(1)} trades/s; request latency p50 ${pct(0.5)}ms p95 ${pct(0.95)}ms max ${latencies[latencies.length - 1]}ms`);
    for (const [k, v] of Object.entries(timings)) { v.sort((a, b) => a - b); console.log(`  ${k}: n=${v.length} avg ${(v.reduce((x, y) => x + y, 0) / v.length).toFixed(0)}ms p50 ${v[Math.floor(v.length / 2)]}ms max ${v[v.length - 1]}ms`); }
    console.log(`node CPU ${((cpu.user + cpu.system) / 1000 / (secs * 1000) * 100).toFixed(0)}% of one core; per rollover ${((cpu.user + cpu.system) / 1000 / Math.max(1, rolled)).toFixed(1)}ms CPU`);
  } finally {
    await mongoose.connection.dropDatabase();
    await mongoose.disconnect();
  }
})().catch(async (e) => { console.error(e); try { await mongoose.connection.dropDatabase(); } catch (_) {} process.exit(1); });
