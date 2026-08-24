/// Converts a number to Indian number system words.
/// e.g. 100000000000 → "1 Kharab" or 1500000 → "15 Lakh"
String numberToIndianWords(double? value) {
  if (value == null || value == 0) return '';

  final num = value.abs();
  final isNegative = value < 0;

  String result;

  if (num >= 1e11) {
    result = '${_format(num / 1e11)} Kharab';
  } else if (num >= 1e9) {
    result = '${_format(num / 1e9)} Arab';
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
