'use strict';

// The banner as sections in one scrolling line (real case 15 Oct 2026: CRUDE
// 19 NOV opened with no notice, and the 08:00 ban list replaces any notice).
let mockRows = [];
const mockMatch = (r, q) => Object.entries(q).every(([k, v]) => {
  if (k === '$or') return v.some((alt) => mockMatch(r, alt));
  if (v && typeof v === 'object' && '$exists' in v) return (r[k] !== undefined) === v.$exists;
  if (v && typeof v === 'object' && '$gt' in v) return r[k] > v.$gt;
  return (r[k] ?? null) === v;
});
jest.mock('../src/models/Announcement', () => ({
  updateMany: async (q, u) => { for (const r of mockRows) if (mockMatch(r, q)) Object.assign(r, u.$set); },
  create: async (doc) => { const r = { _id: `a${mockRows.length}`, createdAt: new Date(Date.now() + mockRows.length), ...doc }; mockRows.push(r); return r; },
  find: (q) => ({ sort: () => ({ lean: async () => mockRows.filter((r) => mockMatch(r, q)) }) }),
}));
const board = require('../src/services/announcementBoard');

beforeEach(() => { mockRows = []; });

const EXPIRY = 'NEW CONTRACT Open 📢\n\nMCX - \n\nCRUDEOIL\nCRUDEOILM\n\nOld Contract settlement: 16-OCT-FRIDAY at last Quotation\n ( 11.30 P.M. )';

test('a multi-line notice becomes one readable line (the app shows only the first line)', () => {
  expect(board.toLine(EXPIRY)).toBe('NEW CONTRACT Open 📢 · MCX - CRUDEOIL · CRUDEOILM · Old Contract settlement: 16-OCT-FRIDAY at last Quotation · ( 11.30 P.M. )');
});

test('the ban list, a new-contract notice and an admin message scroll together', async () => {
  await board.postSection('ban', 'NSE F&O Ban (15 Oct 2026): KAYNES');
  await board.postSection('expiry', EXPIRY, { ref: '2026-10-15', expiresAt: new Date(Date.now() + 3600e3) });
  await board.postSection('manual', 'Market holiday on 21 Oct');
  const { message } = await board.activeBanner();
  expect(message.split(board.SEPARATOR)).toEqual(['Market holiday on 21 Oct', board.toLine(EXPIRY), 'NSE F&O Ban (15 Oct 2026): KAYNES']);
});

test("the next day's ban list replaces only yesterday's list", async () => {
  await board.postSection('expiry', EXPIRY, { ref: '2026-10-15' });
  await board.postSection('ban', 'NSE F&O Ban (15 Oct 2026): KAYNES');
  await board.postSection('ban', 'NSE F&O Ban (16 Oct 2026): SAIL');
  const { message } = await board.activeBanner();
  expect(message).toContain('SAIL');
  expect(message).not.toContain('KAYNES');
  expect(message).toContain('CRUDEOILM');
});

test('a day with no bans removes the ban section; notices of different open days both stay', async () => {
  await board.postSection('ban', 'NSE F&O Ban (15 Oct 2026): KAYNES');
  await board.postSection('expiry', 'NEW CONTRACT Open 📢\nMCX -\nCRUDEOIL', { ref: '2026-10-15' });
  await board.postSection('expiry', 'NEW CONTRACT Open 📢\nNSE -\nALL NSE FUTURES', { ref: '2026-10-26' });
  await board.clearSection('ban');
  const { message } = await board.activeBanner();
  expect(message).not.toContain('Ban');
  expect(message).toContain('CRUDEOIL');
  expect(message).toContain('ALL NSE FUTURES');
});

test('a notice drops off after the old contract has settled', async () => {
  await board.postSection('expiry', EXPIRY, { ref: '2026-10-15', expiresAt: new Date(Date.now() - 1000) });
  expect(await board.activeBanner()).toBeNull();
});

test('an old single-slot announcement counts as the admin message and is replaced by the next one', async () => {
  mockRows.push({ _id: 'old', message: 'legacy', is_active: true, createdAt: new Date(0) });
  await board.postSection('manual', 'new admin message');
  expect((await board.activeBanner()).message).toBe('new admin message');
});
