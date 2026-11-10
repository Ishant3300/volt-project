'use strict';

// Kite re-uses instrument_tokens. On 28 Oct 2026 the 07:30 sync wrote 145 new
// NFO JAN futures onto old documents (matched by token): they kept the old
// _id (created Apr–May) and the old contract's enabled flag, so the expiry
// planner — which closes only contracts loaded after NEW_CONTRACTS_CLOSED_FROM
// — left them open. The sync now lists a re-used token like a new contract
// (listed_at, schema-default state), and the planner counts listed_at too.

jest.mock('../src/models/KiteInstrument', () => ({ updateMany: jest.fn(), find: jest.fn(), findOne: jest.fn(), aggregate: jest.fn() }));
jest.mock('../src/models/ExpiryAction', () => ({ find: jest.fn(), updateOne: jest.fn(), findOne: jest.fn() }));

const KiteInstrument = require('../src/models/KiteInstrument');
const ExpiryAction = require('../src/models/ExpiryAction');
const { buildInstrumentUpsertOperation } = require('../scripts/fetchInstruments');
const { NEW_CONTRACTS_CLOSED_FROM } = require('../src/config/expiryRules');
const expiryActionService = require('../src/services/expiryActionService');

const JAN = { instrument_token: '12345', tradingsymbol: 'BANKNIFTY27JANFUT', name: 'BANKNIFTY', expiry: '2027-01-25', instrument_type: 'FUT', segment: 'NFO-FUT', exchange: 'NFO', lot_size: 30 };
const now = new Date('2026-10-28T02:00:17Z');

describe('daily sync: a token Kite re-used for a new contract', () => {
  test('is listed like a new contract: open by default, old ban cleared, listed_at now', () => {
    const op = buildInstrumentUpsertOperation(JAN, { instrument_token: '12345', tradingsymbol: 'BANKNIFTY26MAYFUT', expiry: new Date('2026-05-26') }, now);
    expect(op.updateOne.filter).toEqual({ instrument_token: '12345' });
    expect(op.updateOne.update.$set).toMatchObject({ tradingsymbol: 'BANKNIFTY27JANFUT', enabled: true, ban_reason: null, banned_at: null, listed_at: now });
  });

  test("drops the old contract's prices (10 Nov 2026: NOV futures kept the old last_price)", () => {
    const op = buildInstrumentUpsertOperation(JAN, { instrument_token: '12345', tradingsymbol: 'BANKNIFTY26MAYFUT', expiry: new Date('2026-05-26') }, now);
    expect(op.updateOne.update.$set).toMatchObject({
      last_price: 0, ohlc_open: 0, ohlc_high: 0, ohlc_low: 0, ohlc_close: 0,
      settlement_price: 0, settlement_price_date: null, settlement_price_source: null,
    });
  });

  test('the same contract again keeps its prices (only a re-used token is reset)', () => {
    const op = buildInstrumentUpsertOperation({ ...JAN, last_price: 999 }, { instrument_token: '12345', tradingsymbol: 'BANKNIFTY27JANFUT', expiry: new Date('2027-01-25') }, now);
    for (const f of ['last_price', 'ohlc_close', 'settlement_price', 'settlement_price_date']) expect(op.updateOne.update.$set).not.toHaveProperty(f);
  });

  test('the same contract again changes nothing about its state or listing', () => {
    const op = buildInstrumentUpsertOperation(JAN, { instrument_token: '12345', tradingsymbol: 'BANKNIFTY27JANFUT', expiry: new Date('2027-01-25') }, now);
    expect(op.updateOne.update.$set).not.toHaveProperty('enabled');
    expect(op.updateOne.update.$set).not.toHaveProperty('listed_at');
    expect(op.updateOne.update.$setOnInsert.listed_at).toEqual(now); // only if it is inserted
  });

  test('a brand-new token gets listed_at on insert only', () => {
    const op = buildInstrumentUpsertOperation(JAN, null, now);
    expect(op.updateOne.update.$set).not.toHaveProperty('listed_at');
    expect(op.updateOne.update.$setOnInsert).toMatchObject({ instrument_token: '12345', listed_at: now });
  });
});

describe('expiry planner: closing a newly loaded far month', () => {
  test('matches documents created OR listed after the cut-off (a re-used old _id no longer slips through)', async () => {
    ExpiryAction.find.mockReturnValue({ lean: async () => [{
      _id: 'a1', key: 'NSE_FUT|OPEN|2027-01-25', kind: 'OPEN', group_key: 'NSE_FUT', segments: ['NFO-FUT'], action_date: '2026-12-29',
      targets: [{ name: 'BANKNIFTY', expiry: new Date('2027-01-25T00:00:00Z') }], closed_targets: [],
    }] });
    KiteInstrument.updateMany.mockResolvedValue({ modifiedCount: 1 });
    ExpiryAction.updateOne.mockResolvedValue({});
    await expiryActionService._private.closeNewTargetsUntilOpen(now);
    const [filter, update] = KiteInstrument.updateMany.mock.calls[0];
    expect(filter.$or).toEqual([{ _id: { $gt: expect.anything() } }, { listed_at: { $gt: NEW_CONTRACTS_CLOSED_FROM } }]);
    expect(filter).not.toHaveProperty('_id');
    expect(filter.enabled).toEqual({ $ne: false });
    expect(update.$set).toMatchObject({ enabled: false, ban_reason: 'Opens for trading on 2026-12-29' });
  });
});
