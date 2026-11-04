'use strict';

// MCX futures trade in whole lots only (utils/comexLots.js, 4 Nov 2026) — a web
// order window sent "3" as 3 qty of SILVER (lot 30) and nothing on the server stopped it.

jest.mock('../src/models/KiteInstrument', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/Trade', () => ({ aggregate: jest.fn() }));
const KiteInstrument = require('../src/models/KiteInstrument');
const Trade = require('../src/models/Trade');
const { validateMcxWholeLots } = require('../src/utils/comexLots');

const lean = (v) => { const c = {}; c.select = jest.fn(() => c); c.session = jest.fn(() => c); c.lean = jest.fn(async () => v); return c; };
const agg = (rows) => { const p = Promise.resolve(rows); p.session = jest.fn(() => p); return p; };
const SILVER = { lot_size: 30, name: 'SILVER', tradingsymbol: 'SILVER26DECFUT', segment: 'MCX-FUT' };

beforeEach(() => jest.clearAllMocks());

test('whole lots pass, part lots are refused (400) for every caller', async () => {
  KiteInstrument.findOne.mockReturnValue(lean(SILVER));
  Trade.aggregate.mockReturnValue(agg([]));
  await expect(validateMcxWholeLots({ segment: 'MCX-FUT', exchange: 'MCX', instrument_token: 't', quantity: 90, userId: 'u' })).resolves.toBeUndefined();
  await expect(validateMcxWholeLots({ segment: 'MCX-FUT', exchange: 'MCX', instrument_token: 't', quantity: 3, userId: 'u' }))
    .rejects.toMatchObject({ status: 400, message: expect.stringMatching(/MCX trades in whole lots only — 1 lot of SILVER = 30/) });
  await expect(validateMcxWholeLots({ segment: 'MCX-FUT', exchange: 'MCX', instrument_token: 't', quantity: 2.4, userId: 'u' })).rejects.toMatchObject({ status: 400 });
});

test('an order that closes the whole open part-lot position is allowed; a partial one is not', async () => {
  KiteInstrument.findOne.mockReturnValue(lean(SILVER));
  Trade.aggregate.mockReturnValue(agg([{ _id: null, net: 3 }]));
  await expect(validateMcxWholeLots({ segment: 'MCX-FUT', instrument_token: 't', quantity: 3, userId: 'u' })).resolves.toBeUndefined();
  Trade.aggregate.mockReturnValue(agg([{ _id: null, net: -2.4 }]));
  await expect(validateMcxWholeLots({ segment: 'MCX-FUT', instrument_token: 't', quantity: 2.4, userId: 'u' })).resolves.toBeUndefined();
  Trade.aggregate.mockReturnValue(agg([{ _id: null, net: 90 }]));
  await expect(validateMcxWholeLots({ segment: 'MCX-FUT', instrument_token: 't', quantity: 3, userId: 'u' })).rejects.toMatchObject({ status: 400 });
});

test('a trade row (exchange MCX, no segment) is checked through the instrument', async () => {
  KiteInstrument.findOne.mockReturnValue(lean(SILVER));
  Trade.aggregate.mockReturnValue(agg([]));
  await expect(validateMcxWholeLots({ exchange: 'MCX', instrument_token: 't', quantity: 3, userId: 'u' })).rejects.toMatchObject({ status: 400 });
});

test('other segments and lot-size-1 scripts are untouched', async () => {
  await validateMcxWholeLots({ segment: 'NSE', exchange: 'NSE', instrument_token: 't', quantity: 7 });
  expect(KiteInstrument.findOne).not.toHaveBeenCalled();
  KiteInstrument.findOne.mockReturnValue(lean({ ...SILVER, segment: 'NFO-FUT' }));
  await expect(validateMcxWholeLots({ exchange: 'NFO', instrument_token: 't', quantity: 7 })).resolves.toBeUndefined();
  KiteInstrument.findOne.mockReturnValue(lean({ ...SILVER, lot_size: 1 }));
  await expect(validateMcxWholeLots({ segment: 'MCX-FUT', instrument_token: 't', quantity: 7 })).resolves.toBeUndefined();
});

describe('options (NFO-OPT, MCX-OPT, BFO-OPT): whole lots only too (4 Nov 2026)', () => {
  const NIFTY_CE = { lot_size: 65, name: 'NIFTY', tradingsymbol: 'NIFTY26NOV24000CE', segment: 'NFO-OPT' };

  test('NSE option: 130 passes, 50 is refused with an options message', async () => {
    KiteInstrument.findOne.mockReturnValue(lean(NIFTY_CE));
    Trade.aggregate.mockReturnValue(agg([]));
    await expect(validateMcxWholeLots({ segment: 'NFO-OPT', exchange: 'NFO', instrument_token: 't', quantity: 130, userId: 'u' })).resolves.toBeUndefined();
    await expect(validateMcxWholeLots({ segment: 'NFO-OPT', exchange: 'NFO', instrument_token: 't', quantity: 50, userId: 'u' }))
      .rejects.toMatchObject({ status: 400, message: expect.stringMatching(/Options trade in whole lots only — 1 lot of NIFTY = 65/) });
  });

  test('MCX and BSE options too; a trade row (exchange only) is checked via the instrument', async () => {
    Trade.aggregate.mockReturnValue(agg([]));
    KiteInstrument.findOne.mockReturnValue(lean({ ...NIFTY_CE, segment: 'MCX-OPT', lot_size: 100 }));
    await expect(validateMcxWholeLots({ exchange: 'MCX', instrument_token: 't', quantity: 30, userId: 'u' })).rejects.toMatchObject({ status: 400 });
    KiteInstrument.findOne.mockReturnValue(lean({ ...NIFTY_CE, segment: 'BFO-OPT', lot_size: 20 }));
    await expect(validateMcxWholeLots({ exchange: 'BFO', instrument_token: 't', quantity: 10, userId: 'u' })).rejects.toMatchObject({ status: 400 });
  });

  test('closing a whole part-lot option position is still allowed; NFO futures untouched', async () => {
    KiteInstrument.findOne.mockReturnValue(lean(NIFTY_CE));
    Trade.aggregate.mockReturnValue(agg([{ _id: null, net: -50 }]));
    await expect(validateMcxWholeLots({ segment: 'NFO-OPT', instrument_token: 't', quantity: 50, userId: 'u' })).resolves.toBeUndefined();
    KiteInstrument.findOne.mockReturnValue(lean({ ...NIFTY_CE, segment: 'NFO-FUT' }));
    await expect(validateMcxWholeLots({ segment: 'NFO-FUT', exchange: 'NFO', instrument_token: 't', quantity: 7 })).resolves.toBeUndefined();
  });
});
