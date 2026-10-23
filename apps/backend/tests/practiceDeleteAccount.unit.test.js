'use strict';

// Practice backend only: a practice client can delete their own account from
// the app (App Store guideline 5.1.1(v)). Soft delete, pending orders cancelled
// and taken off the order book, email freed for a new sign-up. Live keeps 403.

jest.mock('../src/models/User', () => ({ findOne: jest.fn(), updateOne: jest.fn() }));
jest.mock('../src/models/Trade', () => ({ find: jest.fn() }));
jest.mock('../src/services/orderBookService', () => ({ removeOrder: jest.fn() }));

const User = require('../src/models/User');
const Trade = require('../src/models/Trade');
const orderBookService = require('../src/services/orderBookService');
const { deletePracticeAccount } = require('../src/controllers/practiceAccountController');

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };

beforeEach(() => jest.clearAllMocks());

test('client: pending orders cancelled, account soft-deleted, email freed', async () => {
  User.findOne.mockResolvedValue({ _id: 'u1', username: 'asha@example.com' });
  const order = { _id: 't1', instrument_token: 1, transaction_type: 'BUY', order_type: 'LIMIT', trigger_direction: null, status: 'pending', save: jest.fn() };
  Trade.find.mockResolvedValue([order]);
  const r = res();
  await deletePracticeAccount({ user: { id: 'u1' } }, r);
  expect(r.status).toHaveBeenCalledWith(200);
  expect(order.status).toBe('cancelled');
  expect(order.save).toHaveBeenCalled();
  expect(orderBookService.removeOrder).toHaveBeenCalledWith('t1', 1, 'BUY', 'LIMIT', null);
  const [filter, update] = User.updateOne.mock.calls[0];
  expect(filter).toEqual({ _id: 'u1' });
  expect(update.$set.active_status).toBe(false);
  expect(update.$set.deleted_at).toBeInstanceOf(Date);
  expect(update.$set.username).toMatch(/^asha@example\.com#deleted-\d+$/);
});

test('not a client (master/admin token): refused, nothing changed', async () => {
  const r = res();
  await deletePracticeAccount({ master: { id: 'm1' } }, r);
  expect(r.status).toHaveBeenCalledWith(403);
  expect(User.updateOne).not.toHaveBeenCalled();
});

test('already deleted / unknown: 404', async () => {
  User.findOne.mockResolvedValue(null);
  const r = res();
  await deletePracticeAccount({ user: { id: 'u9' } }, r);
  expect(r.status).toHaveBeenCalledWith(404);
  expect(User.updateOne).not.toHaveBeenCalled();
});

test('the route: practice gets the delete, live keeps the 403', () => {
  const load = (practice) => {
    let router;
    jest.isolateModules(() => {
      jest.doMock('../src/config/practice', () => ({ PRACTICE: practice }));
      router = require('../src/routes/authRoutes');
    });
    const layer = router.stack.find((l) => l.route && l.route.path === '/account' && l.route.methods.delete);
    return layer.route.stack.map((s) => s.handle.name);
  };
  expect(load(true)).toContain('deletePracticeAccount');
  expect(load(false)).not.toContain('deletePracticeAccount');
});
