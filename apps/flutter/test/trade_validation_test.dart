import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/views/trade_card_view.dart';

void main() {
  group('local option sell validation', () {
    test(
        'admin-selected user is always deferred to backend ownership validation',
        () {
      final error = validateLocalOptionSell(
        isAdmin: true,
        isOption: true,
        transactionType: 'SELL',
        requestedQuantity: 30,
        knownNetQuantity: null,
      );

      expect(error, isNull);
    });

    test('missing local metrics do not reject a potentially owned option', () {
      final error = validateLocalOptionSell(
        isAdmin: false,
        isOption: true,
        transactionType: 'SELL',
        requestedQuantity: 30,
        knownNetQuantity: null,
      );

      expect(error, isNull);
    });

    test('known local holding still prevents an obvious oversell', () {
      final error = validateLocalOptionSell(
        isAdmin: false,
        isOption: true,
        transactionType: 'SELL',
        requestedQuantity: 60,
        knownNetQuantity: 30,
      );

      expect(error, 'You can only sell up to 30 units (your current holding).');
    });

    test('known local holding permits a full close', () {
      final error = validateLocalOptionSell(
        isAdmin: false,
        isOption: true,
        transactionType: 'SELL',
        requestedQuantity: 30,
        knownNetQuantity: 30,
      );

      expect(error, isNull);
    });
  });
}
