'use strict';

// Rejection Log coverage: every business refusal of a client's order is saved
// (previously max 0 / exchange-not-allowed / banned / NFO-window refusals left
// no trace), and the mobile app can report orders it blocked before sending.

jest.mock('../src/models/Trade', () => {
  const Trade = { find: jest.fn(), create: jest.fn(), countDocuments: jest.fn() };
  Trade.schema = { path: () => ({ enumValues: ['NSE', 'NFO', 'MCX', 'NSEIX', 'GLOBAL', 'COMEX'] }) };
  return Trade;
});
jest.mock('../src/models/User', () => ({ findById: jest.fn() }));
jest.mock('../src/models/KiteInstrument', () => ({ findOne: jest.fn() }));

const Trade = require('../src/models/Trade');
const User = require('../src/models/User');
const KiteInstrument = require('../src/models/KiteInstrument');
const { isLoggableTradeRefusal, buildAppBlockRemark } = require('../src/utils/rejectionLog');
const { MESSAGE: NFO_WINDOW_MESSAGE } = require('../src/utils/nfoMarketOnlyWindow');
const { recordAppRejection } = require('../src/controllers/rejectionLogController');

const lean = (v) => ({ select: () => ({ lean: async () => v }), lean: async () => v });

describe('isLoggableTradeRefusal', () => {
  test.each([
    'CRUDEOILM is not allowed for this account — no quantity allotted (max 0). Existing positions can only be closed.',
    'Your account is not permitted to trade NFO-OPT. Contact your master/admin.',
    NFO_WINDOW_MESSAGE,
    'This script is under NSE F&O ban (MWPL limit exceeded). You cannot open new positions on this script.',
    'This instrument has been disabled by admin. You can only close your existing 50 qty position. Cannot open new positions on this script.',
    'Admin has deactivated this script. Trading is not allowed.',
    'This contract has expired and can no longer be traded.',
    'Trading is blocked: a margin square-off already closed all your positions. Contact your master/admin to add credit and resume.',
    'Order size exceeds breakup limit. Max lots per order: 1, Requested: 2 lot(s). Please split your order.',
    'Insufficient MCX wallet balance. Required ₹1.00.',
  ])('saves: %s', (msg) => expect(isLoggableTradeRefusal(msg)).toBe(true));

  test.each([
    'User not found',
    'Not authorized to place a trade for this user',
    'WriteConflict error: this operation conflicted with another operation',
    'connection timed out',
    '',
    undefined,
  ])('does not save internal/auth error: %s', (msg) => expect(isLoggableTradeRefusal(msg)).toBe(false));
});

describe('buildAppBlockRemark', () => {
  test('fixed label + what the client saw', () => {
    expect(buildAppBlockRemark('STALE_QUOTE', "Low volume — price hasn't updated recently."))
      .toBe('Blocked in app: Price not updated in the app for 25s (stale quote) — "Low volume — price hasn\'t updated recently."');
  });
  test('unknown code is refused', () => expect(buildAppBlockRemark('ANYTHING', 'x')).toBeNull());
  test('detail is trimmed, single-line and capped', () => {
    const r = buildAppBlockRemark('MAX_LOTS', `a\n\tb ${'x'.repeat(500)}`);
    expect(r).not.toMatch(/[\n\t]/);
    expect(r.length).toBeLessThan(300);
  });
});

describe('POST /api/trade/app-rejection', () => {
  const res = () => {
    const r = {};
    r.status = jest.fn(() => r);
    r.json = jest.fn(() => r);
    return r;
  };
  const USER = '6abe43e224b6774d9f87abe0';
  const body = {
    instrument_token: '145894407', transaction_type: 'BUY', quantity: 100, order_type: 'MARKET', price: 8822,
    code: 'STALE_QUOTE', message: 'Low volume', tradingsymbol: 'SPOOFED',
  };

  beforeEach(() => {
    jest.clearAllMocks();
    KiteInstrument.findOne.mockReturnValue(lean({ tradingsymbol: 'CRUDEOIL26OCTFUT', exchange: 'MCX' }));
    Trade.find.mockReturnValue(lean([]));
    User.findById.mockReturnValue(lean({ master_id: 'm1', server_id: 's1' }));
    Trade.create.mockResolvedValue({});
  });

  test('stores a rejected trade with server-side symbol and built remark', async () => {
    const r = res();
    await recordAppRejection({ user: { id: USER }, body }, r);
    expect(r.status).toHaveBeenCalledWith(201);
    const doc = Trade.create.mock.calls[0][0];
    expect(doc).toMatchObject({
      status: 'rejected', tradingsymbol: 'CRUDEOIL26OCTFUT', exchange: 'MCX', transaction_type: 'BUY',
      quantity: 100, executed_quantity: 0, instrument_token: '145894407',
    });
    expect(doc.remarks).toMatch(/^Blocked in app: Price not updated/);
  });

  test('masters/admins cannot use it', async () => {
    const r = res();
    await recordAppRejection({ master: { id: 'x' }, body }, r);
    expect(r.status).toHaveBeenCalledWith(403);
    expect(Trade.create).not.toHaveBeenCalled();
  });

  test('unknown reason code or bad token is refused', async () => {
    for (const b of [{ ...body, code: 'FREE_TEXT' }, { ...body, instrument_token: '$where' }, { ...body, transaction_type: 'HOLD' }]) {
      const r = res();
      await recordAppRejection({ user: { id: USER }, body: b }, r);
      expect(r.status).toHaveBeenCalledWith(400);
    }
    expect(Trade.create).not.toHaveBeenCalled();
  });

  test('same block within 10s is not stored twice', async () => {
    const remarks = buildAppBlockRemark('STALE_QUOTE', 'Low volume');
    Trade.find.mockReturnValue(lean([{ instrument_token: '145894407', remarks, createdAt: new Date(Date.now() - 3000) }]));
    const r = res();
    await recordAppRejection({ user: { id: USER }, body }, r);
    expect(r.status).toHaveBeenCalledWith(200);
    expect(Trade.create).not.toHaveBeenCalled();
  });

  test('at most 30 per user per minute', async () => {
    Trade.find.mockReturnValue(lean(Array.from({ length: 30 }, () => ({ instrument_token: '1', remarks: 'x', createdAt: new Date() }))));
    const r = res();
    await recordAppRejection({ user: { id: USER }, body }, r);
    expect(Trade.create).not.toHaveBeenCalled();
  });
});
