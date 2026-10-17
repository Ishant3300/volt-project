import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/watchlist_provider.dart';

// Order screen opened for a script NOT in the watchlist (Positions / History /
// Reports / option chain): its ticks must reach the order screen, or the
// 25 s stale-quote guard blocks every order.
void main() {
  WatchlistItem seed(String token) => WatchlistItem(
        id: 'pos_$token',
        instrument: KiteInstrument.fromJson({
          'instrument_token': token,
          'tradingsymbol': 'DMART26OCTFUT',
          'exchange': 'NFO',
          'segment': 'NFO-FUT',
        }),
        currentPrice: 4000,
        bidPrice: 3999,
        askPrice: 4001,
        lastUpdated: DateTime.now().subtract(const Duration(minutes: 5)),
      );

  test('tracked script receives ticks; fresh tick time only from a real tick', () {
    final p = WatchlistProvider();
    expect(p.getByToken('111'), isNull);

    p.track(seed('111'));
    final t = p.getByToken('111');
    expect(t, isNotNull);
    expect(t!.lastUpdated, isNull); // never trusts the caller's old copy
    expect(t.currentPrice, 4000);
    expect(p.items, isEmpty); // not shown in the watchlist

    p.updatePrice('111', price: 4010, bidPrice: 4009, askPrice: 4011);
    final u = p.getByToken('111')!;
    expect(u.currentPrice, 4010);
    expect(u.askPrice, 4011);
    expect(DateTime.now().difference(u.lastUpdated!).inSeconds, lessThan(2));
  });

  test('ref-counted: stays until the last order screen for it closes', () {
    final p = WatchlistProvider();
    p.track(seed('222'));
    p.track(seed('222'));
    p.untrack('222');
    expect(p.getByToken('222'), isNotNull);
    p.untrack('222');
    expect(p.getByToken('222'), isNull);
    p.updatePrice('222', price: 1); // ignored, no crash
    expect(p.getByToken('222'), isNull);
  });

  test('a cached / settlement price is shown but is not a fresh tick', () {
    final p = WatchlistProvider();
    p.track(seed('444'));
    p.updatePrice('444', price: 3900, bidPrice: 3900, askPrice: 3900, genuine: false);
    final c = p.getByToken('444')!;
    expect(c.currentPrice, 3900);
    expect(c.lastUpdated, isNull); // guard still waits for a live tick
    p.updatePrice('444', price: 3950);
    expect(p.getByToken('444')!.lastUpdated, isNotNull);
  });

  test('clearAll (logout) drops tracked scripts', () {
    final p = WatchlistProvider();
    p.track(seed('333'));
    p.clearAll();
    expect(p.getByToken('333'), isNull);
  });
}
