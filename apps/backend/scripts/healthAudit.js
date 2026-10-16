'use strict';

/**
 * READ-ONLY daily health audit — data side (DB, Redis order book, contracts,
 * expiry schedule, positions, wallets). Run by scripts/dailyHealthAudit.sh
 * (pm2 cron, trading days 8:45 AM + 4:15 PM IST), which adds the process /
 * feed / log checks and saves the report to ~/audit/. Lines start with
 * OK / WARN / FAIL.
 */
require('dotenv').config();
const m = require('mongoose');
const Redis = require('ioredis');

const out = [];
const ok = (s) => out.push(`OK    ${s}`);
const warn = (s) => out.push(`WARN  ${s}`);
const bad = (s) => out.push(`FAIL  ${s}`);
const istDate = (offsetDays = 0) => new Date(Date.now() + 5.5 * 3600e3 + offsetDays * 864e5).toISOString().slice(0, 10);

(async () => {
  await m.connect(process.env.MONGO_URI);
  const db = m.connection.db;
  const s = process.hrtime.bigint();
  await db.command({ ping: 1 });
  const ping = Number(process.hrtime.bigint() - s) / 1e6;
  (ping < 20 ? ok : warn)(`MongoDB reachable, ping ${ping.toFixed(1)} ms`);

  // Redis + pending orders present in the order book
  const r = new Redis(process.env.REDIS_URL || 'redis://127.0.0.1:6379', { maxRetriesPerRequest: 2 });
  const mem = await r.info('memory');
  ok(`Redis reachable, ${(mem.match(/used_memory_human:(\S+)/) || [])[1]} used`);
  const pend = await db.collection('trades').find({ status: 'pending', order_type: { $in: ['LIMIT', 'SL', 'SL-M'] }, deleted_at: null })
    .project({ instrument_token: 1, transaction_type: 1, order_type: 1, trigger_direction: 1 }).toArray();
  let missing = 0;
  for (const t of pend) {
    const stop = ['SL', 'SL-M'].includes(t.order_type);
    const key = stop
      ? `ob:${t.instrument_token}:${(t.trigger_direction || (t.transaction_type === 'BUY' ? 'RISE' : 'FALL')) === 'FALL' ? 'stopfall' : 'stoprise'}`
      : `ob:${t.instrument_token}:${t.transaction_type === 'BUY' ? 'buy' : 'sell'}`;
    if ((await r.zscore(key, String(t._id))) == null) missing++;
  }
  (missing === 0 ? ok : bad)(`Pending orders ${pend.length}, missing from Redis order book: ${missing}`);
  await r.quit();

  const K = db.collection('kiteinstruments');
  const today = new Date(); today.setHours(0, 0, 0, 0);

  // Futures: every script needs an open month; more than one open month = opened early
  const rows = await K.aggregate([
    { $match: { segment: { $in: ['NFO-FUT', 'MCX-FUT', 'COMEX-FUT'] }, instrument_type: 'FUT', is_active: true, deleted_at: null, expiry: { $gte: today } } },
    { $sort: { expiry: 1 } },
    { $group: { _id: { seg: '$segment', name: '$name' }, list: { $push: { e: '$expiry', en: '$enabled' } } } },
  ]).toArray();
  const none = rows.filter((x) => !x.list.some((y) => y.en !== false)).map((x) => `${x._id.seg} ${x._id.name}`);
  // A second open month is normal in the roll-over window: expiry management
  // opened it (done OPEN action) and the old month hasn't been cut yet
  // (CRUDE NOV opened 15 Oct, OCT settles 16 Oct). Only a month opened any
  // other way is a warning.
  const scheduled = new Set();
  for (const a of await db.collection('expiryactions').find({ kind: 'OPEN', status: 'done' }).project({ targets: 1 }).toArray()) {
    for (const t of a.targets || []) scheduled.add(`${String(t.name).toUpperCase()}|${new Date(t.expiry).toISOString().slice(0, 10)}`);
  }
  const rolling = []; const many = [];
  for (const x of rows) {
    const open = x.list.filter((y) => y.en !== false);
    if (open.length < 2) continue;
    const extra = open.slice(1).map((y) => `${String(x._id.name).toUpperCase()}|${new Date(y.e).toISOString().slice(0, 10)}`);
    (extra.every((k) => scheduled.has(k)) ? rolling : many).push(`${x._id.seg} ${x._id.name}`);
  }
  (none.length ? bad : ok)(`Futures scripts with NO open contract: ${none.length}${none.length ? ' — ' + none.join(', ') : ''}`);
  (many.length ? warn : ok)(`Futures scripts with more than one open month (not opened by expiry management): ${many.length}${many.length ? ' — ' + many.join(', ') : ''}`);
  if (rolling.length) ok(`Next month open per expiry schedule (roll-over window): ${rolling.join(', ')}`);

  // GIFT NIFTY monthly: all must be ACTIVE (visible); at least one OPEN.
  // A later month closed until its open day is correct, not a problem.
  const gift = await K.find({ exchange: 'NSEIX', instrument_type: 'FUT', expiry: { $gte: today }, deleted_at: null })
    .project({ tradingsymbol: 1, is_active: 1, enabled: 1 }).sort({ expiry: 1 }).toArray();
  const inactive = gift.filter((g) => g.is_active !== true).map((g) => g.tradingsymbol);
  const openGift = gift.filter((g) => g.enabled !== false).map((g) => g.tradingsymbol);
  (inactive.length ? bad : ok)(`GIFT NIFTY contracts inactive (hidden from search/watchlist): ${inactive.length}${inactive.length ? ' — ' + inactive.join(', ') : ''}`);
  (openGift.length ? ok : bad)(`GIFT NIFTY open contract: ${openGift.join(', ') || 'NONE'}`);

  // Expiry schedule
  const todayKey = istDate();
  const acts = db.collection('expiryactions');
  const overdue = await acts.find({ action_date: { $lt: todayKey }, status: { $in: ['planned', 'confirmed'] } })
    .project({ _id: 0, group_key: 1, kind: 1, action_date: 1, status: 1 }).toArray();
  const failed = await acts.find({ status: { $in: ['failed', 'error'] } }).project({ _id: 0, group_key: 1, kind: 1, action_date: 1 }).toArray();
  const cutsSoon = await acts.find({ kind: 'CUT', status: 'planned', action_date: { $gte: todayKey, $lte: istDate(3) } })
    .project({ _id: 0, group_key: 1, action_date: 1 }).toArray();
  const opensToday = await acts.find({ kind: 'OPEN', action_date: todayKey }).project({ _id: 0, group_key: 1, status: 1 }).toArray();
  (overdue.length ? bad : ok)(`Expiry actions overdue: ${overdue.length}${overdue.length ? ' — ' + overdue.map((a) => `${a.action_date} ${a.group_key} ${a.kind} ${a.status}`).join('; ') : ''}`);
  (failed.length ? bad : ok)(`Expiry actions failed: ${failed.length}${failed.length ? ' — ' + failed.map((a) => `${a.action_date} ${a.group_key} ${a.kind}`).join('; ') : ''}`);
  (cutsSoon.length ? warn : ok)(`Cuts in next 3 days still needing admin confirm: ${cutsSoon.length}${cutsSoon.length ? ' — ' + cutsSoon.map((a) => `${a.action_date} ${a.group_key}`).join('; ') : ''}`);
  if (opensToday.length) ok(`New contracts opening today: ${opensToday.map((a) => `${a.group_key} (${a.status})`).join(', ')}`);

  // Positions left in contracts that already expired (last 14 days)
  const expiredToks = (await K.find({ expiry: { $lt: today, $gte: new Date(today.getTime() - 14 * 864e5) }, deleted_at: null })
    .project({ instrument_token: 1 }).toArray()).map((i) => String(i.instrument_token));
  const stuck = expiredToks.length ? await db.collection('trades').aggregate([
    { $match: { instrument_token: { $in: expiredToks }, status: 'completed', deleted_at: null } },
    { $group: { _id: { u: '$user_id', t: '$tradingsymbol' }, net: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', { $multiply: ['$executed_quantity', -1] }] } } } },
    { $match: { net: { $ne: 0 } } },
  ]).toArray() : [];
  (stuck.length ? bad : ok)(`Open positions left in expired contracts: ${stuck.length}${stuck.length ? ' — ' + stuck.slice(0, 10).map((p) => `${p._id.t}:${p.net}`).join(', ') : ''}`);

  // Contracts expiring today that still have open positions (closed automatically at 3:31/3:46/11:33)
  const tomorrow = new Date(today.getTime() + 864e5);
  const expToday = (await K.find({ expiry: { $gte: today, $lt: tomorrow }, deleted_at: null }).project({ instrument_token: 1 }).toArray()).map((i) => String(i.instrument_token));
  if (expToday.length) {
    const openToday = await db.collection('trades').aggregate([
      { $match: { instrument_token: { $in: expToday }, status: 'completed', deleted_at: null } },
      { $group: { _id: { u: '$user_id', t: '$instrument_token' }, net: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', { $multiply: ['$executed_quantity', -1] }] } } } },
      { $match: { net: { $ne: 0 } } },
    ]).toArray();
    ok(`Contracts expiring today: ${expToday.length}; open positions in them now: ${openToday.length} (auto-closed at expiry)`);
  }

  // Wallets
  const neg = await db.collection('users').countDocuments({ deleted_at: null, $or: ['NSE', 'NSEOPT', 'MCX', 'COMEX', 'GLOBAL'].map((c) => ({ [`wallet.${c}`]: { $lt: 0 } })) });
  (neg ? warn : ok)(`Client accounts with a negative trade wallet: ${neg}`);

  // Activity
  const start = new Date(`${todayKey}T00:00:00+05:30`);
  const tToday = await db.collection('trades').countDocuments({ createdAt: { $gte: start } });
  const rejToday = await db.collection('trades').countDocuments({ createdAt: { $gte: start }, status: 'rejected' });
  ok(`Trades today so far: ${tToday} (rejected ${rejToday})`);

  console.log(out.join('\n'));
  await m.disconnect();
  process.exit(0);
})().catch((e) => { console.log(`FAIL  data audit crashed: ${e.message}`); process.exit(1); });
