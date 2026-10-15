#!/usr/bin/env node
/**
 * One-time switch of the live banner to sections (services/announcementBoard.js),
 * run right after the deploy that introduces them:
 *  - today's active NSE ban-list row (from before sections) becomes the 'ban' section
 *  - a new-contract notice is posted for every open day whose old contract
 *    hasn't settled yet (e.g. CRUDE 19 NOV opened 15 Oct, settles 16 Oct 23:30)
 * Safe to run again. `--dry` prints only.
 */
require('dotenv').config();
const mongoose = require('mongoose');

(async () => {
  const dry = process.argv.includes('--dry');
  await mongoose.connect(process.env.MONGO_URI);
  const Announcement = require('../src/models/Announcement');
  const ExpiryAction = require('../src/models/ExpiryAction');
  const expiry = require('../src/services/expiryActionService');
  const board = require('../src/services/announcementBoard');

  const legacyBan = await Announcement.find({ is_active: true, source: { $exists: false }, message: /^NSE F&O Ban/ }).lean();
  console.log(`legacy ban-list rows to tag: ${legacyBan.length}`);
  if (!dry && legacyBan.length) await Announcement.updateMany({ _id: { $in: legacyBan.map((r) => r._id) } }, { $set: { source: 'ban' } });
  // A new-contract notice published by hand before sections (15 Oct 09:12)
  // is replaced by the dated 'expiry' section posted below.
  const legacyNotice = await Announcement.find({ is_active: true, source: { $exists: false }, message: /^NEW CONTRACT Open/ }).lean();
  console.log(`legacy new-contract notices to replace: ${legacyNotice.length}`);
  if (!dry && legacyNotice.length) await Announcement.updateMany({ _id: { $in: legacyNotice.map((r) => r._id) } }, { $set: { is_active: false } });

  const now = new Date();
  const days = [...new Set((await ExpiryAction.find({ kind: 'OPEN', status: 'done', action_date: { $gte: new Date(now - 10 * 864e5).toISOString().slice(0, 10) } }).select('action_date').lean()).map((a) => a.action_date))].sort();
  for (const day of days) {
    const draft = await expiry.buildAnnouncement(day);
    if (!draft.message || draft.expires_at <= now) { console.log(`${day}: settled already, no notice`); continue; }
    console.log(`${day}: notice until ${draft.expires_at.toISOString()} — ${board.toLine(draft.message)}`);
    if (!dry) await board.postSection('expiry', draft.message, { ref: day, expiresAt: draft.expires_at });
  }
  const banner = await board.activeBanner();
  console.log(`banner now: ${banner ? banner.message : '(empty)'}`);
  await mongoose.disconnect();
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
