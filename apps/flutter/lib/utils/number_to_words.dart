/// Converts a number to Indian number system words.
/// e.g. 1500000 → "15 Lakh", 250000000 → "25 Crore", 1000000000000 → "1 Lakh
/// Crore" — stays in Crore/Lakh Crore terms, never rolls over into the rarer
/// Arab/Kharab units regardless of magnitude.
String numberToIndianWords(double? value) {
  if (value == null || value == 0) return '';

  final num = value.abs();
  final isNegative = value < 0;

  String result;

  if (num >= 1e12) {
    result = '${_format(num / 1e12)} Lakh Crore';
  } else if (num >= 1e7) {
    result = '${_format(num / 1e7)} Crore';
  } else if (num >= 1e5) {
    result = '${_format(num / 1e5)} Lakh';
  } else if (num >= 1e3) {
    result = '${_format(num / 1e3)} Thousand';
  } else {
    result = _format(num);
  }

  return isNegative ? '- $result' : result;
}

String _format(double n) {
  if (n == n.roundToDouble() && n < 10000) return n.toInt().toString();
  if (n >= 100) return n.toStringAsFixed(0);
  if (n >= 10) return n.toStringAsFixed(1);
  return n.toStringAsFixed(2);
}
