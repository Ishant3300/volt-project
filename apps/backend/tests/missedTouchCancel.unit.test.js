'use strict';

// A client's own cancel/modify of a pending LIMIT/SL first asks
// missedTouchService whether the exchange already traded through the order
// between two feed updates (27 Oct 2026). If it did, the order has just filled
// and the client is told so; otherwise the change goes ahead as before. A
// master's or admin's change is never held up by it.
//
// Cancel and modify only change an order that is STILL pending at the values
// they checked (conditional update): a fill committing in between — a tick, or
// the missed-touch check itself — used to be overwritten by an unconditional
// save ('cancelled' over a completed trade, a new price on a completed trade).

jest.mock('../src/models/Trade', () => ({ findOne: jest.fn(), findById: jest.fn(), updateOne: jest.fn() }));
jest.mock('../src/services/orderBookService', () => ({ removeOrder: jest.fn(), addOrder: jest.fn() }));
jest.mock('../src/services/tradeWriteFenceService', () => ({ beginTradeWrite: jest.fn(), withTradeWriteLease: jest.fn((_n, fn) => fn()) }));
const mockCheck = jest.fn();
jest.mock('../src/services/missedTouchService', () => ({ checkBeforeChange: (...a) => mockCheck(...a), dayRangeTouch: () => null }));

const Trade = require('../src/models/Trade');
const orderBookService = require('../src/services/orderBookService');
const tc = require('../src/controllers/tradeController');
const { cancelTrade, modifyTrade } = tc;

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const freshIs = (doc) => Trade.findById.mockReturnValue({ select: () => ({ lean: async () => doc }) });
let trade;
beforeEach(() => {
  jest.clearAllMocks();
  trade = {
    _id: 'sl1', user_id: { toString: () => 'u1' }, master_id: { toString: () => 'm1' }, status: 'pending', order_type: 'SL',
    transaction_type: 'SELL', price: 9502, quantity: 100, instrument_token: '146796039', trigger_direction: null,
    save: jest.fn().mockResolvedValue(undefined),
  };
  Trade.findOne.mockResolvedValue(trade);
  Trade.updateOne.mockResolvedValue({ modifiedCount: 1 });
  freshIs({ status: 'completed', executed_price: 9502 });
  mockCheck.mockResolvedValue({ checked: true, executed: false });
});

test('client cancel, price already traded through: answered "already executed", not cancelled', async () => {
  mockCheck.mockResolvedValue({ checked: true, executed: true });
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, user: { id: 'u1' } }, r);
  expect(mockCheck).toHaveBeenCalledWith(trade);
  expect(r.status).toHaveBeenCalledWith(400);
  expect(r.json).toHaveBeenCalledWith({ success: false, message: 'This order was already executed at 9502: the price traded there before your cancel.' });
  expect(Trade.updateOne).not.toHaveBeenCalled();
  expect(orderBookService.removeOrder).not.toHaveBeenCalled();
});

test('client cancel, not traded through: cancelled only while still pending, then removed from the book', async () => {
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, user: { id: 'u1' } }, r);
  expect(Trade.updateOne).toHaveBeenCalledWith({ _id: 'sl1', status: 'pending', deleted_at: null }, { $set: { status: 'cancelled' } });
  expect(trade.save).not.toHaveBeenCalled();
  expect(orderBookService.removeOrder).toHaveBeenCalledWith('sl1', '146796039', 'SELL', 'SL', null);
  expect(r.status).toHaveBeenCalledWith(200);
});

test('a fill that commits during the cancel is never overwritten', async () => {
  Trade.updateOne.mockResolvedValue({ modifiedCount: 0 });
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, user: { id: 'u1' } }, r);
  expect(r.status).toHaveBeenCalledWith(400);
  expect(r.json).toHaveBeenCalledWith({ success: false, message: 'This order was already executed at 9502.' });
  expect(orderBookService.removeOrder).not.toHaveBeenCalled();
});

test('a check that throws never blocks the cancel', async () => {
  mockCheck.mockRejectedValue(new Error('kite down'));
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, user: { id: 'u1' } }, r);
  expect(Trade.updateOne).toHaveBeenCalled();
  expect(r.status).toHaveBeenCalledWith(200);
});

test("an admin's cancel is not checked", async () => {
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, admin: { id: 'a1' } }, r);
  expect(mockCheck).not.toHaveBeenCalled();
  expect(r.status).toHaveBeenCalledWith(200);
});

test('client modify, price already traded through: answered before any validation, order untouched', async () => {
  mockCheck.mockResolvedValue({ checked: true, executed: true });
  const r = res();
  await modifyTrade({ params: { tradeId: 'sl1' }, body: { price: 9490 }, user: { id: 'u1' } }, r);
  expect(r.status).toHaveBeenCalledWith(400);
  expect(r.json).toHaveBeenCalledWith({ success: false, message: 'This order was already executed at 9502: the price traded there before your change.' });
  expect(trade.price).toBe(9502);
  expect(orderBookService.removeOrder).not.toHaveBeenCalled();
});
