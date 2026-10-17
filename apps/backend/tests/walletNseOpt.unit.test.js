'use strict';

// NSE options ("NSE OPT") have their own wallet pool, NSEOPT: option margin is
// blocked from and released to wallet.NSEOPT only — never the NSE (futures)
// pool — with the same never-negative guard as every other pool.

jest.mock('../src/models/User', () => ({ updateOne: jest.fn(), findById: jest.fn() }));
jest.mock('../src/models/Master', () => ({ updateOne: jest.fn(), findById: jest.fn() }));

const User = require('../src/models/User');
const walletService = require('../src/services/walletService');
const { categoryForSegment } = require('../src/utils/walletCategory');

beforeEach(() => jest.clearAllMocks());

const lean = (doc) => ({ select: () => ({ lean: async () => doc }) });

test('NSEOPT is a valid pool; NSE futures and options resolve to different pools', () => {
  expect(walletService.CATEGORIES).toEqual(['NSE', 'INDEX', 'NSEOPT', 'MCX', 'COMEX', 'GLOBAL']);
  expect(categoryForSegment('NFO-OPT')).toBe('NSEOPT');
  expect(categoryForSegment('NFO-FUT')).toBe('NSE');
});

test('block on an option position debits wallet.NSEOPT with the never-negative guard', async () => {
  User.updateOne.mockResolvedValue({ matchedCount: 1 });
  await walletService.block('User', 'u1', categoryForSegment('NFO-OPT'), 12500.456);
  expect(User.updateOne).toHaveBeenCalledWith(
    { _id: 'u1', 'wallet.NSEOPT': { $gte: 12500.46 } },
    { $inc: { 'wallet.NSEOPT': -12500.46 } },
    {},
  );
});

test('block fails with INSUFFICIENT_WALLET naming NSEOPT when the options pool is short (NSE untouched)', async () => {
  User.updateOne.mockResolvedValue({ matchedCount: 0 });
  await expect(walletService.block('User', 'u1', 'NSEOPT', 5000))
    .rejects.toMatchObject({ code: walletService.INSUFFICIENT_WALLET, category: 'NSEOPT', requested: 5000 });
  expect(User.updateOne).toHaveBeenCalledTimes(1);
  expect(JSON.stringify(User.updateOne.mock.calls[0])).not.toContain('"wallet.NSE"');
});

test('closing an option releases to wallet.NSEOPT', async () => {
  User.updateOne.mockResolvedValue({ matchedCount: 1 });
  await walletService.release('User', 'u1', categoryForSegment('NFO-OPT'), 800);
  expect(User.updateOne).toHaveBeenCalledWith({ _id: 'u1' }, { $inc: { 'wallet.NSEOPT': 800 } }, {});
});

test('futures still use wallet.NSE', async () => {
  User.updateOne.mockResolvedValue({ matchedCount: 1 });
  await walletService.block('User', 'u1', categoryForSegment('NFO-FUT'), 100);
  expect(User.updateOne).toHaveBeenCalledWith(
    { _id: 'u1', 'wallet.NSE': { $gte: 100 } }, { $inc: { 'wallet.NSE': -100 } }, {},
  );
});

test('getAvailable returns NSEOPT, reading a missing field (older documents) as 0', async () => {
  User.findById.mockReturnValue(lean({ wallet: { NSE: 1000, MCX: 5 } }));
  expect(await walletService.getAvailable('User', 'u1')).toEqual({ NSE: 1000, INDEX: 0, NSEOPT: 0, MCX: 5, COMEX: 0, GLOBAL: 0 });
  User.findById.mockReturnValue(lean({ wallet: { NSE: 1000, NSEOPT: 250.5 } }));
  expect((await walletService.getAvailable('User', 'u1')).NSEOPT).toBe(250.5);
});

test('an unknown pool is still rejected', async () => {
  await expect(walletService.block('User', 'u1', 'OPT', 1)).rejects.toThrow(/invalid category/);
});

// INDEX pool (Oct 2026): NIFTY / BANKNIFTY / SENSEX futures — same shape as NSEOPT.
test('INDEX is a valid pool; an older document without it reads 0 and accepts funding', async () => {
  expect(walletService.CATEGORIES).toContain('INDEX');
  User.findById.mockReturnValue(lean({ wallet: { NSE: 1000, NSEOPT: 50 } }));
  expect((await walletService.getAvailable('User', 'u1')).INDEX).toBe(0);
  User.findById.mockReturnValue(lean({ wallet: { NSE: 1000, INDEX: 750.25 } }));
  expect((await walletService.getAvailable('User', 'u1')).INDEX).toBe(750.25);
});

test('index futures and stock futures resolve to different pools', () => {
  expect(categoryForSegment('NFO-FUT', { name: 'NIFTY' })).toBe('INDEX');
  expect(categoryForSegment('NFO-FUT', { name: 'RELIANCE' })).toBe('NSE');
});
