import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/utils/script_name.dart';

void main() {
  test('GLOBAL / COMEX tickers get the long name with the platform expiry day', () {
    expect(scriptLabel('YMZ6'), 'DOW JONES 30 18 DEC');
    expect(scriptLabel('ESZ6'), 'S&P 500 18 DEC');
    expect(scriptLabel('NQH7'), 'NASDAQ 100 19 MAR');
    expect(scriptLabel('RTYZ6'), 'RUSSELL 2000 18 DEC');
    expect(scriptLabel('NKDZ6'), 'NIKKEI 225 10 DEC');
    expect(scriptLabel('GCZ6'), 'GOLD 30 NOV');
    expect(scriptLabel('GCG7'), 'GOLD 29 JAN');
    expect(scriptLabel('SIH7'), 'SILVER 26 FEB');
    expect(scriptLabel('HGZ6'), 'COPPER 30 NOV');
  });

  test('a known expiry and name win over the derived ones', () {
    expect(scriptLabel('YMZ6', name: 'Dow Jones 30', expiry: '2026-12-18T00:00:00.000Z'), 'DOW JONES 30 18 DEC');
    expect(scriptLabel('ESH7', expiry: DateTime.utc(2027, 3, 18)), 'S&P 500 18 MAR');
  });

  test('every other symbol is shown unchanged', () {
    for (final s in ['GOLD26DECFUT', 'RELIANCE', 'SIZE', 'NIFTY2611825000CE', '']) {
      expect(scriptLabel(s), s);
    }
    expect(globalScriptName('RELIANCE'), isNull);
  });
}
