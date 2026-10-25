'use strict';

// COMEX trades in whole lots only, like MCX (utils/comexLots.js, 25 Oct 2026).

jest.mock('../src/models/KiteInstrument', () => ({ findOne: jest.fn() }));
const KiteInstrument = require('../src/models/KiteInstrument');
const { tradingModeFor, validateComexWholeLots } = require('../src/utils/comexLots');

const lean = (v) => { const c = {}; c.select = jest.fn(() => c); c.session = jest.fn(() => c); c.lean = jest.fn(async () => v); return c; };
const GOLD = { lot_size: 100, name: 'Gold', tradingsymbol: 'GCX6', segment: 'COMEX-FUT' };

beforeEach(() => jest.clearAllMocks());

test('a ticked COMEX row trades in lots whatever is ticked; the tick itself and other segments are untouched', () => {
  const comexTurnover = { exchange_name: 'COMEX-FUT', turnover: true, lot: false };
  expect(tradingModeFor(comexTurnover, 'COMEX-FUT')).toEqual({ lot: true, turnover: false });
  expect(comexTurnover).toEqual({ exchange_name: 'COMEX-FUT', turnover: true, lot: false }); // not modified
  expect(tradingModeFor({ exchange_name: 'COMEX-FUT', turnover: false, lot: false }, 'COMEX-FUT')).toEqual({ lot: false, turnover: false }); // unticked = not allowed, unchanged
  expect(tradingModeFor({ exchange_name: 'MCX-FUT', turnover: true, lot: false }, 'MCX-FUT')).toEqual({ lot: false, turnover: true });
  expect(tradingModeFor(undefined, 'COMEX-FUT')).toEqual({ lot: false, turnover: false });
});

test('COMEX quantity must be whole lots of the official contract size', async () => {
  KiteInstrument.findOne.mockReturnValue(lean(GOLD));
  await expect(validateComexWholeLots({ segment: 'COMEX-FUT', exchange: 'COMEX', instrument_token: 't', quantity: 200 })).resolves.toBeUndefined();
  await expect(validateComexWholeLots({ exchange: 'COMEX', instrument_token: 't', quantity: 150 }))
    .rejects.toMatchObject({ status: 400, message: expect.stringMatching(/whole lots only — 1 lot of Gold = 100/) });
  await expect(validateComexWholeLots({ exchange: 'COMEX', instrument_token: 't', quantity: 1 })).rejects.toMatchObject({ status: 400 });
});

test('non-COMEX orders are not looked up at all', async () => {
  await validateComexWholeLots({ segment: 'MCX-FUT', exchange: 'MCX', instrument_token: 't', quantity: 7 });
  expect(KiteInstrument.findOne).not.toHaveBeenCalled();
});
