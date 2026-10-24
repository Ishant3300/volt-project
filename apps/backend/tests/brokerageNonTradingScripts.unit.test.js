'use strict';

// Brokerage rows for scripts that trade in no segment (e.g. 11 F&O stocks
// dropped from F&O) never feed a trade, so they must not block a floor check,
// and a whole-segment rate set at account creation must cover them too.
// Real case 24 Oct 2026: NBS (593462) kept the global default 2 on those 11
// stocks after "NFO-FUT 1 for all", and a master's "1 for all" then failed
// with "Brokerage cannot be less than the parent limit (2)".

jest.mock('../src/models/BrokerageSettings', () => ({ find: jest.fn(), findOne: jest.fn(), bulkWrite: jest.fn().mockResolvedValue({}) }));
jest.mock('../src/models/KiteInstrument', () => ({ find: jest.fn(), distinct: jest.fn() }));
jest.mock('../src/models/User', () => ({ findById: jest.fn() }));
jest.mock('../src/models/Master', () => ({ findById: jest.fn() }));

const BrokerageSettings = require('../src/models/BrokerageSettings');
const KiteInstrument = require('../src/models/KiteInstrument');
const User = require('../src/models/User');
const { applyBrokerageOverrides, validateBrokerageFloor, tradingScriptNames } = require('../src/services/brokerageCopyService');

const chain = (result) => { const c = {}; c.select = jest.fn(() => c); c.session = jest.fn(() => c); c.lean = jest.fn(() => Promise.resolve(result)); return c; };
// 100+ trading names so the guard trusts the list; RELIANCE trades, DALBHARAT doesn't.
const TRADING = ['RELIANCE', 'NIFTY', ...Array.from({ length: 100 }, (_, i) => `S${i}`)];

beforeEach(() => {
  jest.clearAllMocks();
  KiteInstrument.distinct.mockImplementation(async (field) => (field === 'raw_name' ? TRADING : []));
});

test('tradingScriptNames: too few names → null (treat everything as trading)', async () => {
  KiteInstrument.distinct.mockResolvedValue(['RELIANCE']);
  expect(await tradingScriptNames()).toBeNull();
});

test('validateBrokerageFloor: non-trading script has no floor; trading script still checked', async () => {
  User.findById.mockReturnValue(chain({ master_id: 'parent' }));
  BrokerageSettings.findOne.mockReturnValue(chain({ brk_value: 2 }));
  expect(await validateBrokerageFloor('u1', 'User', 'NFO-FUT', 'DALBHARAT', 'TURNOVER WISE', 1)).toBeNull();
  expect(await validateBrokerageFloor('u1', 'User', 'NFO-FUT', 'RELIANCE', 'TURNOVER WISE', 1)).toMatch(/parent limit \(2\)/);
});

test('validateBrokerageFloor: guard (bad instrument list) keeps today\'s check', async () => {
  KiteInstrument.distinct.mockResolvedValue([]);
  User.findById.mockReturnValue(chain({ master_id: 'parent' }));
  BrokerageSettings.findOne.mockReturnValue(chain({ brk_value: 2 }));
  expect(await validateBrokerageFloor('u1', 'User', 'NFO-FUT', 'DALBHARAT', 'TURNOVER WISE', 1)).toMatch(/parent limit \(2\)/);
});

test('whole-segment override also sets the account\'s non-trading rows, with no floor check', async () => {
  KiteInstrument.find.mockReturnValue(chain([{ raw_name: 'RELIANCE' }]));
  BrokerageSettings.findOne.mockReturnValue(chain({ brk_value: 1 })); // RELIANCE floor 1 → ok
  BrokerageSettings.find.mockReturnValue(chain([
    { _id: 'r1', script_name: 'RELIANCE' },  // already covered above
    { _id: 'd1', script_name: 'DALBHARAT' }, // trades nowhere, copied at 2
  ]));
  await applyBrokerageOverrides('child', [{ exchange_name: 'NFO-FUT', type: 'TURNOVER WISE', brk_value: 1 }], null, true);
  const ops = BrokerageSettings.bulkWrite.mock.calls[0][0];
  expect(ops).toHaveLength(2);
  expect(ops[0].updateOne.filter.script_name).toBe('RELIANCE');
  expect(ops[1].updateOne).toEqual({ filter: { _id: 'd1', deleted_at: null }, update: { $set: { brk_value: 1, updated_at: expect.any(Date) } } });
  expect(BrokerageSettings.findOne).toHaveBeenCalledTimes(1); // floor checked for RELIANCE only
});

test('category override touches only non-trading rows of that category', async () => {
  KiteInstrument.find.mockReturnValue(chain([{ raw_name: 'RELIANCE' }, { raw_name: 'NIFTY' }]));
  BrokerageSettings.find.mockReturnValue(chain([{ _id: 'd1', script_name: 'DALBHARAT' }, { _id: 'd2', script_name: 'BANKEX' }]));
  await applyBrokerageOverrides('child', [{ exchange_name: 'NFO-FUT', type: 'TURNOVER WISE', brk_value: 1, category: 'STOCK' }]);
  const ops = BrokerageSettings.bulkWrite.mock.calls[0][0];
  expect(ops.map((o) => o.updateOne.filter.script_name || o.updateOne.filter._id)).toEqual(['RELIANCE', 'd1']);
});

test('single-script override: unchanged, no extra rows', async () => {
  await applyBrokerageOverrides('child', [{ exchange_name: 'NFO-FUT', type: 'TURNOVER WISE', brk_value: 1, script_name: 'RELIANCE' }]);
  expect(BrokerageSettings.find).not.toHaveBeenCalled();
  expect(BrokerageSettings.bulkWrite.mock.calls[0][0]).toHaveLength(1);
});
