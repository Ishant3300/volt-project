/// Wallet category for a segment (display only; backend is authoritative).
/// NFO-FUT/NFO-OPT -> NSE; MCX-FUT/MCX-OPT -> MCX; COMEX-FUT -> COMEX;
/// everything else -> GLOBAL.
String categoryForSegment(String? segment) {
  final s = (segment ?? '').trim().toUpperCase();
  if (s == 'NFO-FUT' || s == 'NFO-OPT') return 'NSE';
  if (s == 'MCX-FUT' || s == 'MCX-OPT') return 'MCX';
  if (s == 'COMEX-FUT') return 'COMEX';
  return 'GLOBAL';
}

/// Distinct allowed categories from a list of segment/exchange names.
List<String> allowedCategories(Iterable<String> segments) {
  final found = <String>{for (final seg in segments) categoryForSegment(seg)};
  return ['NSE', 'MCX', 'COMEX', 'GLOBAL'].where(found.contains).toList();
}
