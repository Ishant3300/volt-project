import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/utils/usual_brokerage.dart';

void main() {
  test('NBS case: 218 scripts at 1, 11 non-trading at 2 -> 1', () {
    final items = [
      ...List.generate(11, (_) => {'brk_value': 2}),
      ...List.generate(218, (_) => {'brk_value': 1}),
    ];
    expect(usualBrokerage(items), 1.0);
  });
  test('tie -> higher (safer floor); empty -> null', () {
    expect(usualBrokerage([{'brk_value': 1}, {'brk_value': 2}]), 2.0);
    expect(usualBrokerage([]), isNull);
  });
}
