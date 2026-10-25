'use strict';

// Settings lists hide scripts that trade nowhere (utils/hideNonTrading.js, 25 Oct 2026).

jest.mock('../src/services/brokerageCopyService', () => ({ tradingScriptNames: jest.fn() }));
const { tradingScriptNames } = require('../src/services/brokerageCopyService');
const { withoutNonTrading, _resetCache } = require('../src/utils/hideNonTrading');

const Model = (names) => ({ distinct: jest.fn(async () => names) });

beforeEach(() => { jest.clearAllMocks(); _resetCache(); });

test('agri / dead MCX names are excluded; trading names stay (case-insensitive)', async () => {
  tradingScriptNames.mockResolvedValue(new Set(['GOLD', 'CRUDEOIL', 'SILVERM']));
  const M = Model(['GOLD', 'COTTON', 'KAPAS', 'crudeoil', 'MENTHAOIL', 'SILVERM']);
  const f = await withoutNonTrading(M, { exchange_name: 'MCX-FUT', deleted_at: null }, 'script_name');
  expect(f).toEqual({ exchange_name: 'MCX-FUT', deleted_at: null, script_name: { $nin: ['COTTON', 'KAPAS', 'MENTHAOIL'] } });
  expect(M.distinct).toHaveBeenCalledWith('script_name', { exchange_name: 'MCX-FUT', deleted_at: null });
});

test('nothing dead → filter unchanged', async () => {
  tradingScriptNames.mockResolvedValue(new Set(['GOLD']));
  const filter = { exchange_name: 'MCX-FUT' };
  expect(await withoutNonTrading(Model(['GOLD']), filter, 'raw_name')).toBe(filter);
});

test('broken instrument list (null) hides nothing and skips the distinct query', async () => {
  tradingScriptNames.mockResolvedValue(null);
  const M = Model(['COTTON']);
  const filter = { exchange_name: 'MCX-FUT' };
  expect(await withoutNonTrading(M, filter, 'script_name')).toBe(filter);
  expect(M.distinct).not.toHaveBeenCalled();
});

test('trading names are cached for a minute', async () => {
  tradingScriptNames.mockResolvedValue(new Set(['GOLD']));
  await withoutNonTrading(Model(['GOLD']), {}, 'script_name');
  await withoutNonTrading(Model(['GOLD']), {}, 'script_name');
  expect(tradingScriptNames).toHaveBeenCalledTimes(1);
});
