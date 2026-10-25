'use strict';

// Master base profit book time (utils/profitBookTime.js, 25 Oct 2026): admin
// sets any master's base, a master sets its own sub-masters' bases (never its
// own); the chain always holds; raising a base lifts the whole tree below.

jest.mock('../src/models/Master', () => ({ find: jest.fn(), findOne: jest.fn(), findById: jest.fn(), updateMany: jest.fn(), updateOne: jest.fn(), countDocuments: jest.fn() }));
jest.mock('../src/models/User', () => ({ updateMany: jest.fn(), countDocuments: jest.fn() }));
jest.mock('../src/services/masterHierarchyService', () => ({ getAllSubMasterIds: jest.fn() }));

const mongoose = require('mongoose');
const Master = require('../src/models/Master');
const User = require('../src/models/User');
const { getAllSubMasterIds } = require('../src/services/masterHierarchyService');
const pbt = require('../src/utils/profitBookTime');
const { setProfitBookBase, getProfitBookBase } = require('../src/controllers/profitBookBaseController');

const lean = (v) => { const c = {}; c.select = jest.fn(() => c); c.session = jest.fn(() => c); c.lean = jest.fn(async () => v); return c; }; // query-like: select/session chain, lean resolves
const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const ID = (n) => `6adc4bf86c546769ad3bd${String(n).padStart(3, '0')}`;

beforeEach(() => {
  jest.clearAllMocks();
  jest.spyOn(mongoose, 'startSession').mockResolvedValue({ withTransaction: async (fn) => fn(), endSession: async () => {} });
});

test('client / sub-master time below the base is refused with the reason; at or above is fine', () => {
  expect(pbt.parseProfitBookMinutes(8, { min: 10, minWhy: 'base of harry' }).error).toBe('Profit book time cannot be less than 10 minutes (base of harry)');
  expect(pbt.parseProfitBookMinutes(10, { min: 10 })).toEqual({ value: 10 });
  expect(pbt.parseProfitBookMinutes(30, { min: 10 })).toEqual({ value: 30 });
  expect(pbt.parseProfitBookMinutes(0, { min: null })).toEqual({ value: 0 }); // top-level master: no floor
  expect(pbt.baseOf({})).toBe(10);
  expect(pbt.baseOf({ profit_book_base_minutes: 15 })).toBe(15);
});

test('liftTree raises every lower sub-master base and client time in the whole tree', async () => {
  Master.find.mockReturnValueOnce(lean([{ _id: 'sub1' }, { _id: 'sub2' }])).mockReturnValueOnce(lean([{ _id: 'subsub' }])).mockReturnValueOnce(lean([]));
  Master.updateMany.mockResolvedValue({ modifiedCount: 2 });
  User.updateMany.mockResolvedValue({ modifiedCount: 7 });
  expect(await pbt.liftTree('top', 20)).toEqual({ masters: 2, clients: 7 });
  const [mf, mu] = Master.updateMany.mock.calls[0];
  expect(mf._id.$in).toEqual(['sub1', 'sub2', 'subsub']);
  expect(mf.$or[0]).toEqual({ profit_book_base_minutes: { $lt: 20 } });
  expect(mu.$set.profit_book_base_minutes).toBe(20);
  const [uf, uu] = User.updateMany.mock.calls[0];
  expect(uf.master_id.$in).toEqual(['top', 'sub1', 'sub2', 'subsub']);
  expect(uf.profit_book_minutes).toEqual({ $lt: 20 });
  expect(uu.$set.profit_book_minutes).toBe(20);
});

test('a master cannot set its own base', async () => {
  getAllSubMasterIds.mockResolvedValue([ID(1), ID(2)]);
  const r = res();
  await setProfitBookBase({ params: { masterId: ID(1) }, body: { minutes: 15 }, master: { id: ID(1) } }, r);
  expect(r.status).toHaveBeenCalledWith(403);
  expect(Master.updateOne).not.toHaveBeenCalled();
});

test('a sub-master cannot go below its parent — admin included', async () => {
  Master.findOne.mockReturnValue(lean({ _id: ID(2), username: 'sub', master_id: ID(1), profit_book_base_minutes: 15 }));
  Master.findById.mockReturnValue(lean({ username: 'harry', profit_book_base_minutes: 10 }));
  const r = res();
  await setProfitBookBase({ params: { masterId: ID(2) }, body: { minutes: 8 }, admin: { id: 'a1' } }, r);
  expect(r.status).toHaveBeenCalledWith(400);
  expect(r.json.mock.calls[0][0].message).toMatch(/cannot be less than 10 minutes \(base of harry\)/);
  expect(Master.updateOne).not.toHaveBeenCalled();
});

test('raising a base sets it and lifts the tree in one transaction', async () => {
  getAllSubMasterIds.mockResolvedValue([ID(1), ID(2)]);
  Master.findOne.mockReturnValue(lean({ _id: ID(2), username: 'sub', master_id: ID(1), profit_book_base_minutes: 10 }));
  Master.findById.mockReturnValue(lean({ username: 'harry', profit_book_base_minutes: 10 }));
  Master.find.mockReturnValue(lean([]));
  Master.updateMany.mockResolvedValue({ modifiedCount: 0 });
  User.updateMany.mockResolvedValue({ modifiedCount: 4 });
  const r = res();
  await setProfitBookBase({ params: { masterId: ID(2) }, body: { minutes: 20 }, master: { id: ID(1) } }, r);
  expect(Master.updateOne).toHaveBeenCalledWith({ _id: ID(2) }, { $set: { profit_book_base_minutes: 20 } }, expect.anything());
  expect(r.json.mock.calls[0][0].data).toEqual({ minutes: 20, previous: 10, lifted: { masters: 0, clients: 4 } });
});

test('a top-level master has no floor (admin can set 0)', async () => {
  Master.findOne.mockReturnValue(lean({ _id: ID(1), username: 'harry', master_id: null, profit_book_base_minutes: 10 }));
  Master.find.mockReturnValue(lean([]));
  Master.updateMany.mockResolvedValue({ modifiedCount: 0 });
  User.updateMany.mockResolvedValue({ modifiedCount: 0 });
  const r = res();
  await setProfitBookBase({ params: { masterId: ID(1) }, body: { minutes: 0 }, admin: { id: 'a1' } }, r);
  expect(r.json.mock.calls[0][0].data.minutes).toBe(0);
});

test('GET returns the base and the floor', async () => {
  Master.findOne.mockReturnValue(lean({ _id: ID(2), username: 'sub', master_id: ID(1), profit_book_base_minutes: 15 }));
  Master.findById.mockReturnValue(lean({ username: 'harry', profit_book_base_minutes: 10 }));
  const r = res();
  await getProfitBookBase({ params: { masterId: ID(2) }, admin: { id: 'a1' } }, r);
  expect(r.json).toHaveBeenCalledWith({ success: true, data: { minutes: 15, floor: 10, username: 'sub', parent_username: 'harry' } });
});
