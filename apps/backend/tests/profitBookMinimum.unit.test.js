'use strict';

// Admin minimum profit book time (24 Oct 2026): default 5; a new client starts
// at it and no client's time may be SET below it; a client already below a
// since-raised minimum keeps their time until it's changed.

jest.mock('../src/models/PlatformSetting', () => ({ findOne: jest.fn(), updateOne: jest.fn() }));
const PlatformSetting = require('../src/models/PlatformSetting');
const pbt = require('../src/utils/profitBookTime');
const { getProfitBookMinimum, setProfitBookMinimum } = require('../src/controllers/platformSettingController');

const lean = (v) => ({ lean: async () => v });
const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
beforeEach(() => { jest.clearAllMocks(); pbt.clearMinCache(); });

test('minimum defaults to 5 when never set', async () => {
  PlatformSetting.findOne.mockReturnValue(lean(null));
  expect(await pbt.getMinProfitBookMinutes()).toBe(5);
});

test('minimum comes from the admin setting and is cached', async () => {
  PlatformSetting.findOne.mockReturnValue(lean({ value: 8 }));
  expect(await pbt.getMinProfitBookMinutes()).toBe(8);
  expect(await pbt.getMinProfitBookMinutes()).toBe(8);
  expect(PlatformSetting.findOne).toHaveBeenCalledTimes(1);
});

test('below the minimum is refused; at/above is fine; unchanged current value is kept', () => {
  expect(pbt.parseProfitBookMinutes(4, { min: 5 }).error).toMatch(/cannot be less than 5 minutes/);
  expect(pbt.parseProfitBookMinutes(0, { min: 5 }).error).toMatch(/cannot be less than 5/);
  expect(pbt.parseProfitBookMinutes(5, { min: 5 })).toEqual({ value: 5 });
  expect(pbt.parseProfitBookMinutes(10, { min: 5 })).toEqual({ value: 10 });
  // admin raised the minimum to 15; a client on 10 can still be saved unchanged...
  expect(pbt.parseProfitBookMinutes(10, { min: 15, current: 10 })).toEqual({ value: 10 });
  // ...but changing it must reach the minimum
  expect(pbt.parseProfitBookMinutes(12, { min: 15, current: 10 }).error).toMatch(/cannot be less than 15/);
  expect(pbt.parseProfitBookMinutes(0, { min: 0 })).toEqual({ value: 0 }); // minimum 0 = no floor
});

test('PUT sets the minimum (whole minutes 0-1440) and clears the cache', async () => {
  PlatformSetting.findOne.mockReturnValue(lean({ value: 5 }));
  await pbt.getMinProfitBookMinutes();
  const r = res();
  await setProfitBookMinimum({ body: { minutes: 7 }, admin: { id: 'a1' } }, r);
  expect(PlatformSetting.updateOne).toHaveBeenCalledWith({ key: 'profit_book_min_minutes' }, { $set: { value: 7, updated_by: { type: 'Admin', id: 'a1' } } }, { upsert: true });
  PlatformSetting.findOne.mockReturnValue(lean({ value: 7 }));
  expect(await pbt.getMinProfitBookMinutes()).toBe(7);
  for (const bad of [-1, 2.5, 'x', 1441, undefined]) {
    const rb = res();
    await setProfitBookMinimum({ body: { minutes: bad }, admin: { id: 'a1' } }, rb);
    expect(rb.status).toHaveBeenCalledWith(400);
  }
});

test('GET returns the minimum', async () => {
  PlatformSetting.findOne.mockReturnValue(lean(null));
  const r = res();
  await getProfitBookMinimum({}, r);
  expect(r.json).toHaveBeenCalledWith({ success: true, data: { minutes: 5 } });
});
