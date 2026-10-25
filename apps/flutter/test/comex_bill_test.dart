import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/utils/comex_bill.dart';

// COMEX on the bill (utils/comex_bill.dart): same rule and numbers as the
// backend's tests/comexFx.unit.test.js and the web's lib/comexBill.ts.
void main() {
  const fx = {'base': 88, 'spread': 1};

  test('debit uses base + spread, credit base - spread', () {
    expect(comexRateForNet(-10000, fx), 89);
    expect(comexRateForNet(10000, fx), 87);
    expect(comexRateForNet(0, fx), 88);
    expect(comexRateForNet(5, null), isNull);
  });

  test('settled week at its booked rate, the unsettled rest an estimate at today\'s rate', () {
    final b = comexBill(
      usdPnl: 7000,
      usdBr: 60,
      usdBuyTurnover: 400000,
      usdSellTurnover: 0,
      hasComex: true,
      serverComex: {
        'fx': fx,
        'settled': [
          {'settlement_date': '2026-10-23T22:20:00.000Z', 'settlement_trading_date': '2026-10-23T00:00:00.000Z', 'fx_rate': 87, 'usd_pnl': 10000, 'usd_brokerage': 40, 'inr_pnl': 870000, 'inr_brokerage': 3480},
        ],
      },
    )!;
    expect(b.usdNet, 6940);
    expect(b.lines.map((l) => [l.usdNet, l.rate, l.inrNet, l.estimate]).toList(), [
      [9960, 87, 866520, false],
      [-3020, 89, -268780, true],
    ]);
    expect(b.lines.first.label, 'Settled 23 Oct 2026');
    expect(b.inrNet, 866520 - 268780);
  });

  test('no rate: no rupee figure invented; no COMEX: no block', () {
    final b = comexBill(usdPnl: 100, usdBr: 0, usdBuyTurnover: 0, usdSellTurnover: 0, hasComex: true, serverComex: null)!;
    expect(b.inrNet, isNull);
    expect(b.lines.single.rate, isNull);
    expect(comexBill(usdPnl: 0, usdBr: 0, usdBuyTurnover: 0, usdSellTurnover: 0, hasComex: false, serverComex: null), isNull);
  });
}
