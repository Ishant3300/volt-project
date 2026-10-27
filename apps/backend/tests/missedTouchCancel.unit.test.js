'use strict';

// A client's own cancel/modify of a pending LIMIT/SL first asks
// missedTouchService whether the exchange already traded through the order
// between two feed updates (27 Oct 2026). If it did, the order has just filled
// and the client is told so; otherwise the change goes ahead as before. A
// master's or admin's change is never held up by it.

jest.mock('../src/models/Trade', () => ({ findOne: jest.fn(), findById: jest.fn() }));
jest.mock('../src/services/orderBookService', () => ({ removeOrder: jest.fn(), addOrder: jest.fn() }));
jest.mock('../src/services/tradeWriteFenceService', () => ({ beginTradeWrite: jest.fn(), withTradeWriteLease: jest.fn((_n, fn) => fn()) }));
const mockCheck = jest.fn();
jest.mock('../src/services/missedTouchService', () => ({ checkBeforeChange: (...a) => mockCheck(...a), dayRangeTouch: () => null }));

const Trade = require('../src/models/Trade');
const orderBookService = require('../src/services/orderBookService');
const { cancelTrade, modifyTrade } = require('../src/controllers/tradeController');

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
let trade;
beforeEach(() => {
  jest.clearAllMocks();
  trade = {
    _id: 'sl1', user_id: { toString: () => 'u1' }, master_id: { toString: () => 'm1' }, status: 'pending', order_type: 'SL',
    transaction_type: 'SELL', price: 9502, quantity: 100, instrument_token: '146796039', trigger_direction: null,
    save: jest.fn().mockResolvedValue(undefined),
  };
  Trade.findOne.mockResolvedValue(trade);
  Trade.findById.mockReturnValue({ select: () => ({ lean: async () => ({ status: 'completed', executed_price: 9502 }) }) });
});

test('client cancel, price already traded through: answered "already executed", not cancelled', async () => {
  mockCheck.mockResolvedValue({ checked: true, executed: true });
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, user: { id: 'u1' } }, r);
  expect(mockCheck).toHaveBeenCalledWith(trade);
  expect(r.status).toHaveBeenCalledWith(400);
  expect(r.json).toHaveBeenCalledWith({ success: false, message: 'This order was already executed at 9502: the price traded there before your cancel.' });
  expect(trade.save).not.toHaveBeenCalled();
  expect(orderBookService.removeOrder).not.toHaveBeenCalled();
});

test('client cancel, not traded through: cancelled exactly as before', async () => {
  mockCheck.mockResolvedValue({ checked: true, executed: false });
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, user: { id: 'u1' } }, r);
  expect(trade.status).toBe('cancelled');
  expect(trade.save).toHaveBeenCalled();
  expect(orderBookService.removeOrder).toHaveBeenCalledWith('sl1', '146796039', 'SELL', 'SL', null);
  expect(r.status).toHaveBeenCalledWith(200);
});

test('a check that throws never blocks the cancel', async () => {
  mockCheck.mockRejectedValue(new Error('kite down'));
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, user: { id: 'u1' } }, r);
  expect(trade.status).toBe('cancelled');
  expect(r.status).toHaveBeenCalledWith(200);
});

test("an admin's cancel is not checked", async () => {
  const r = res();
  await cancelTrade({ params: { tradeId: 'sl1' }, admin: { id: 'a1' } }, r);
  expect(mockCheck).not.toHaveBeenCalled();
  expect(trade.status).toBe('cancelled');
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
