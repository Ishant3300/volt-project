import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/utils/profit_hold.dart';

// Profit-book hold timer (10 Nov 2026): the app locks the closing button only
// when the server would refuse — same cases as backend
// tests/profitBookTime.integration.test.js (predictRefused vs the real check).
void main() {
  final now = DateTime.utc(2026, 11, 10, 6, 0, 0);
  // BUY 10 @100 30 min ago (free) + BUY 10 @106 2 min ago (free in 8 min); avg 103
  final hold = ProfitHold(minutes: 10, avg: 103, freeQty: 10, lots: [HoldLot(10, now.add(const Duration(minutes: 8)))]);

  HoldLock? lock({String side = 'SELL', String type = 'MARKET', double price = 0, double bid = 110, double ask = 111, int qty = 20, int net = 20, ProfitHold? h}) =>
      profitHoldLock(hold: h ?? hold, netQty: net, side: side, orderType: type, price: price, bid: bid, ask: ask, qty: qty, now: now);

  test('long, part old / part new', () {
    expect(lock(qty: 10), isNull); // only the old 10 — allowed
    expect(lock(qty: 15)!.left, const Duration(minutes: 8)); // needs the new lot
    expect(lock(qty: 15)!.freeNow, 10);
    expect(lock(qty: 20), isNotNull);
    expect(lock(qty: 25), isNotNull); // more than held: the held part counts
    expect(lock(bid: 102), isNull); // loss — always allowed
    expect(lock(bid: 103), isNull); // exactly the average is not a profit
    expect(lock(type: 'LIMIT', price: 105, bid: 101), isNotNull); // limit in profit
    expect(lock(type: 'LIMIT', price: 102), isNull); // limit at a loss
    expect(lock(side: 'BUY', qty: 5), isNull); // adding — never held
  });

  test('short position: profit is the ask below the average', () {
    final h = ProfitHold(minutes: 15, avg: 100, freeQty: 0, lots: [HoldLot(10, now.add(const Duration(minutes: 12)))]);
    expect(lock(h: h, net: -10, side: 'BUY', qty: 10, ask: 95), isNotNull);
    expect(lock(h: h, net: -10, side: 'BUY', qty: 10, ask: 105), isNull);
    expect(lock(h: h, net: -10, side: 'BUY', type: 'LIMIT', price: 99, qty: 10, ask: 105), isNotNull);
  });

  test('no hold → no timer; time over → unlocked', () {
    expect(profitHoldLock(hold: null, netQty: 20, side: 'SELL', orderType: 'MARKET', price: 0, bid: 110, ask: 111, qty: 20, now: now), isNull);
    expect(profitHoldLock(hold: hold, netQty: 20, side: 'SELL', orderType: 'MARKET', price: 0, bid: 110, ask: 111, qty: 20, now: now.add(const Duration(minutes: 8))), isNull);
    expect(ProfitHold.fromJson(null), isNull);
    expect(ProfitHold.fromJson({'minutes': 10, 'avg': 1, 'free_qty': 0, 'lots': []}), isNull);
  });

  test('server payload parses; countdown text', () {
    final h = ProfitHold.fromJson({'minutes': 10, 'avg': 58210.5, 'free_qty': 0, 'lots': [{'qty': 30, 'free_at': '2026-11-10T06:06:41.000Z'}]})!;
    expect(h.avg, 58210.5);
    expect(lock(h: h, net: 30, qty: 30, bid: 58245)!.left, const Duration(minutes: 6, seconds: 41));
    expect(formatHoldLeft(const Duration(minutes: 6, seconds: 41)), '6:41');
    expect(formatHoldLeft(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
  });
}
