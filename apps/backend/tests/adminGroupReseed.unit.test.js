'use strict';

// Admin Edit User: switching a client's Group re-copies that exchange's script
// limits from the new group (as the master's Edit User already did). Before
// 23 Oct 2026 this route saved only the group NAME — client 994912 showed
// "HRY 5 LOT" while every limit was still GOLDMIN's, and a 1500 order was
// refused at GOLDMIN's 500-per-order.

jest.mock('../src/models/User', () => ({ findById: jest.fn(), findOne: jest.fn() }));
jest.mock('../src/services/scriptQuantityCopyService', () => ({ reseedUserScriptQuantityForExchange: jest.fn() }));

const User = require('../src/models/User');
const { reseedUserScriptQuantityForExchange: reseed } = require('../src/services/scriptQuantityCopyService');
const { updateUser } = require('../src/controllers/adminController');

function userDoc(groups) {
  return {
    _id: 'u1',
    username: '994912',
    exchanges_allowed: groups.map(([exchange_name, group_name]) => ({ exchange_name, turnover: true, lot: false, group_name })),
    save: jest.fn().mockResolvedValue(),
    toJSON() { return { id: 'u1' }; },
  };
}
const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const edit = (exchanges) => ({ params: { id: 'u1' }, admin: { id: 'a1' }, body: { exchanges_allowed: exchanges } });
const ex = (exchange_name, group_name) => ({ exchange_name, turnover: true, lot: false, group_name });

beforeEach(() => jest.clearAllMocks());

test('group switched → that exchange is re-seeded from the new group, after the save', async () => {
  const u = userDoc([['NFO-FUT', 'GOLDMIN'], ['MCX-FUT', 'GOLDMIN']]);
  User.findById.mockResolvedValue(u);
  const r = res();
  await updateUser(edit([ex('NFO-FUT', 'HRY 5 LOT'), ex('MCX-FUT', 'GOLDMIN')]), r);
  expect(r.status).toHaveBeenCalledWith(200);
  expect(r.status).not.toHaveBeenCalledWith(500);
  expect(u.save).toHaveBeenCalled();
  expect(reseed).toHaveBeenCalledTimes(1);
  expect(reseed).toHaveBeenCalledWith('u1', 'NFO-FUT', 'HRY 5 LOT');
  expect(u.save.mock.invocationCallOrder[0]).toBeLessThan(reseed.mock.invocationCallOrder[0]);
});

test('same group re-sent (an ordinary save) → limits untouched', async () => {
  User.findById.mockResolvedValue(userDoc([['NFO-FUT', 'HRY 5 LOT']]));
  await updateUser(edit([ex('NFO-FUT', 'HRY 5 LOT')]), res());
  expect(reseed).not.toHaveBeenCalled();
});

test('no group in the request (e.g. only turnover/lot changed) → limits untouched', async () => {
  User.findById.mockResolvedValue(userDoc([['NFO-FUT', 'HRY 5 LOT']]));
  await updateUser(edit([{ exchange_name: 'NFO-FUT', turnover: true, lot: true }]), res());
  expect(reseed).not.toHaveBeenCalled();
});

test('newly granted exchange with a group → seeded from it', async () => {
  User.findById.mockResolvedValue(userDoc([['NFO-FUT', 'HRY 5 LOT']]));
  await updateUser(edit([ex('NFO-FUT', 'HRY 5 LOT'), ex('mcx-fut', '2 LOT NEW')]), res());
  expect(reseed).toHaveBeenCalledWith('u1', 'MCX-FUT', '2 LOT NEW');
  expect(reseed).toHaveBeenCalledTimes(1);
});
