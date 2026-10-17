'use strict';

// Admin Bulk Trade Import: index futures skip the wallet margin check and may
// take the client's INDEX pool negative (refilled later). Everything else keeps
// the guarded block.

jest.mock('../src/models/User', () => ({ updateOne: jest.fn(), findById: jest.fn() }));
jest.mock('../src/models/Master', () => ({ updateOne: jest.fn(), findById: jest.fn() }));

const User = require('../src/models/User');
const walletService = require('../src/services/walletService');

beforeEach(() => jest.clearAllMocks());

test('normal block is guarded ($gte) and refuses a short pool', async () => {
  User.updateOne.mockResolvedValue({ matchedCount: 0 });
  await expect(walletService.block('User', 'u1', 'INDEX', 500)).rejects.toMatchObject({ code: 'INSUFFICIENT_WALLET' });
  expect(User.updateOne).toHaveBeenCalledWith({ _id: 'u1', 'wallet.INDEX': { $gte: 500 } }, { $inc: { 'wallet.INDEX': -500 } }, {});
});

test('allowNegative: no balance guard, pool may go below 0', async () => {
  User.updateOne.mockResolvedValue({ matchedCount: 1 });
  await expect(walletService.block('User', 'u1', 'INDEX', 500, null, { allowNegative: true })).resolves.toEqual({ category: 'INDEX', amount: 500 });
  expect(User.updateOne).toHaveBeenCalledWith({ _id: 'u1' }, { $inc: { 'wallet.INDEX': -500 } }, {});
});

describe('User schema', () => {
  const RealUser = jest.requireActual('../src/models/User');
  test('a negative INDEX balance still validates (every trade saves the user)', () => {
    const u = new RealUser();
    u.wallet.INDEX = -2500000;
    const err = u.validateSync(['wallet.INDEX']);
    expect(err?.errors?.['wallet.INDEX']).toBeUndefined();
  });
  test('other pools keep the min 0 guard', () => {
    const u = new RealUser();
    u.wallet.NSE = -1;
    expect(u.validateSync(['wallet.NSE']).errors['wallet.NSE']).toBeDefined();
  });
});
