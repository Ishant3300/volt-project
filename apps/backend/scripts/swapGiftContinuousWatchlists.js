'use strict';

/**
 * One-time (29 Sep 2026): move watchlist entries of the retired continuous
 * "GIFT NIFTY" (token 291849) to the Oct monthly contract GIFTNIFTY26OCTFUT.
 * The retirement (giftNiftyFeedService._retireContinuousIfDue, 4:02 PM IST)
 * closes it for trading but never touches watchlists, and its stored expiry
 * keeps rolling forward, so the normal expired-entry cleanup never removes it.
 *  - owner already has the Oct contract  → the old row is soft-deleted;
 *  - otherwise                            → the row is switched to Oct.
 * Refuses to apply unless the continuous instrument is already retired
 * (enabled: false). Dry run by default; --apply writes.
 *   node scripts/swapGiftContinuousWatchlists.js [--apply]
 */
require('dotenv').config();
const mongoose = require('mongoose');

const APPLY = process.argv.includes('--apply');
const OLD = '291849';
const NEW_SYMBOL = 'GIFTNIFTY26OCTFUT';

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  const K = db.collection('kiteinstruments');
  const W = db.collection('watchlists');
  console.log(`[${new Date().toISOString()}] mode: ${APPLY ? 'APPLY' : 'DRY RUN'}`);

  const oldInst = await K.findOne({ instrument_token: OLD });
  const newInst = await K.findOne({ tradingsymbol: NEW_SYMBOL, exchange: 'NSEIX', deleted_at: null });
  if (!newInst) throw new Error(`${NEW_SYMBOL} not found`);
  console.log(`old: ${oldInst?.tradingsymbol} enabled=${oldInst?.enabled} | new: ${newInst.tradingsymbol} token=${newInst.instrument_token} enabled=${newInst.enabled} active=${newInst.is_active}`);

  const entries = await W.find({ instrument_token: { $in: [OLD, Number(OLD)] }, deleted_at: null }).toArray();
  const toRemove = [];
  const toSwitch = [];
  for (const e of entries) {
    const hasNew = await W.findOne({ owner_id: e.owner_id, owner_type: e.owner_type, instrument_token: { $in: [String(newInst.instrument_token), Number(newInst.instrument_token)] }, deleted_at: null });
    (hasNew ? toRemove : toSwitch).push(e._id);
  }
  console.log(`watchlist rows on GIFT NIFTY: ${entries.length} → switch to ${NEW_SYMBOL}: ${toSwitch.length}, remove (already have it): ${toRemove.length}`);

  if (!APPLY) { await mongoose.disconnect(); process.exit(0); }
  if (oldInst && oldInst.enabled !== false) {
    console.log('NOT applied: continuous GIFT NIFTY is not retired yet (enabled). Nothing changed.');
    await mongoose.disconnect(); process.exit(0);
  }
  const now = new Date();
  const r1 = toSwitch.length
    ? await W.updateMany({ _id: { $in: toSwitch } }, { $set: { instrument_token: String(newInst.instrument_token), kite_instrument_id: newInst._id, updatedAt: now } })
    : { modifiedCount: 0 };
  const r2 = toRemove.length
    ? await W.updateMany({ _id: { $in: toRemove } }, { $set: { deleted_at: now, updatedAt: now } })
    : { modifiedCount: 0 };
  console.log(`applied: switched ${r1.modifiedCount}, removed ${r2.modifiedCount}`);
  await mongoose.disconnect();
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
