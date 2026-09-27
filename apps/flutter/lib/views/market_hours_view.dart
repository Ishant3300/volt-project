import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../utils/contants.dart';

class MarketHoursView extends StatefulWidget {
  const MarketHoursView({super.key});
  @override
  State<MarketHoursView> createState() => _MarketHoursViewState();
}

class _MarketHoursViewState extends State<MarketHoursView> {
  static const _upstoxBase = 'https://api.upstox.com/v2/market';
  static const _exchanges = ['NSE', 'NFO', 'BSE', 'BFO', 'MCX', 'CDS', 'BCD'];

  late DateTime _focusedDay;
  DateTime? _selectedDay;
  String _selectedExchange = 'NSE';

  // holiday date → { description, closed_exchanges[], open_exchanges[] }
  Map<String, Map<String, dynamic>> _holidays = {};
  bool _loadingHolidays = false;

  // cached timings per date string → list of exchange timing maps
  final Map<String, List<Map<String, dynamic>>> _timingsCache = {};
  bool _loadingTimings = false;
  List<Map<String, dynamic>>? _selectedDayTimings;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _fetchHolidays();
    _fetchTimingsForDate(DateTime.now());
  }

  // ── Upstox: holidays for current year ──
  Future<void> _fetchHolidays() async {
    setState(() => _loadingHolidays = true);
    try {
      final res = await http.get(Uri.parse('$_upstoxBase/holidays'), headers: {'Accept': 'application/json'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success') {
          final Map<String, Map<String, dynamic>> map = {};
          for (var h in data['data']) {
            map[h['date']] = {
              'description': h['description'],
              'holiday_type': h['holiday_type'],
              'closed_exchanges': List<String>.from(h['closed_exchanges'] ?? []),
              'open_exchanges': h['open_exchanges'] ?? [],
            };
          }
          if (mounted) setState(() => _holidays = map);
        }
      }
    } catch (e) { log('❌ Holiday fetch error: $e'); }
    finally { if (mounted) setState(() => _loadingHolidays = false); }
  }

  // ── Upstox: timings for a specific date ──
  Future<void> _fetchTimingsForDate(DateTime day) async {
    final key = DateFormat('yyyy-MM-dd').format(day);
    if (_timingsCache.containsKey(key)) {
      setState(() => _selectedDayTimings = _timingsCache[key]);
      return;
    }
    setState(() => _loadingTimings = true);
    try {
      final res = await http.get(Uri.parse('$_upstoxBase/timings/$key'), headers: {'Accept': 'application/json'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success') {
          final List<Map<String, dynamic>> timings = [];
          for (var t in data['data']) {
            timings.add({'exchange': t['exchange'], 'start_time': t['start_time'], 'end_time': t['end_time']});
          }
          _timingsCache[key] = timings;
          if (mounted) setState(() => _selectedDayTimings = timings);
        }
      }
    } catch (e) { log('❌ Timings fetch error: $e'); }
    finally { if (mounted) setState(() => _loadingTimings = false); }
  }

  // ── Is the selected exchange open on a given day? ──
  _DayStatus _getDayStatus(DateTime day) {
    if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
      return _DayStatus.closed;
    }
    final key = DateFormat('yyyy-MM-dd').format(day);
    final holiday = _holidays[key];
    if (holiday == null) return _DayStatus.open; // normal trading day

    final closed = List<String>.from(holiday['closed_exchanges'] ?? []);
    if (closed.contains(_selectedExchange)) return _DayStatus.closed;

    // Check if exchange is in open_exchanges (partial holiday)
    final openExchanges = holiday['open_exchanges'] as List;
    for (var oe in openExchanges) {
      if (oe['exchange'] == _selectedExchange) return _DayStatus.partial;
    }

    // If exchange not in closed and not in open, it's a settlement holiday — treat as open
    if (holiday['holiday_type'] == 'SETTLEMENT_HOLIDAY' && !closed.contains(_selectedExchange)) {
      return _DayStatus.open;
    }

    return _DayStatus.open;
  }

  String _formatEpoch(dynamic epoch) {
    if (epoch == null) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(epoch is int ? epoch : (epoch as num).toInt(), isUtc: false);
    return DateFormat('hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selectedDay ?? DateTime.now();
    final selKey = DateFormat('yyyy-MM-dd').format(sel);
    final holiday = _holidays[selKey];
    final status = _getDayStatus(sel);

    // Find timing for selected exchange on selected day
    Map<String, dynamic>? exchangeTiming;
    if (_selectedDayTimings != null) {
      for (var t in _selectedDayTimings!) {
        if (t['exchange'] == _selectedExchange) { exchangeTiming = t; break; }
      }
    }

    // If it's a partial holiday, check open_exchanges for special timings
    Map<String, dynamic>? holidayTiming;
    if (holiday != null) {
      final openExchanges = holiday['open_exchanges'] as List;
      for (var oe in openExchanges) {
        if (oe['exchange'] == _selectedExchange) { holidayTiming = Map<String, dynamic>.from(oe); break; }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: const Icon(Icons.arrow_back, color: kColorTextPrimary, size: kIconSizeMedium))),
          const SizedBox(width: 12),
          const Text('Market Timings', style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
        ])),

        // Exchange dropdown
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: _selectedExchange, isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down, size: kIconSizeMedium, color: kColorTextMuted),
            style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
            items: _exchanges.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() { _selectedExchange = v!; }),
          )),
        )),
        const SizedBox(height: 12),

        // Calendar + details
        Expanded(child: _loadingHolidays
          ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
          : SingleChildScrollView(child: Column(children: [
            // Calendar card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: TableCalendar(
                firstDay: DateTime(2025, 1, 1), lastDay: DateTime(2027, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
                onDaySelected: (s, f) { setState(() { _selectedDay = s; _focusedDay = f; }); _fetchTimingsForDate(s); },
                onPageChanged: (f) => _focusedDay = f,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                startingDayOfWeek: StartingDayOfWeek.sunday,
                headerStyle: const HeaderStyle(
                  titleCentered: true, formatButtonVisible: false,
                  titleTextStyle: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeButtonText, fontFamily: kFontFamily, fontWeight: kFontWeightBold),
                  leftChevronIcon: Icon(Icons.chevron_left, color: kBrandPrimary, size: 22),
                  rightChevronIcon: Icon(Icons.chevron_right, color: kBrandPrimary, size: 22),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: kColorTextMuted, fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
                  weekendStyle: TextStyle(color: kColorTextMuted, fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  defaultTextStyle: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
                  weekendTextStyle: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
                  todayDecoration: BoxDecoration(color: kBrandPrimary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  todayTextStyle: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightBold),
                  selectedDecoration: const BoxDecoration(color: kBrandPrimary, shape: BoxShape.circle),
                  selectedTextStyle: const TextStyle(color: Colors.white, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightBold),
                  cellMargin: const EdgeInsets.all(4),
                ),
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (ctx, day, events) {
                    final s = _getDayStatus(day);
                    final color = s == _DayStatus.closed ? kColorSell : s == _DayStatus.partial ? const Color(0xFFF59E0B) : kColorBuy;
                    return Positioned(bottom: 4, child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)));
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Selected day detail card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Day label + status badge
                Row(children: [
                  Text(_dayLabel(sel), style: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: 0.5)),
                  const Spacer(),
                  _statusBadge(status),
                ]),
                if (holiday != null) ...[
                  const SizedBox(height: 6),
                  Text(holiday['description'] ?? '', style: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium, fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 12),

                if (_loadingTimings)
                  const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kBrandPrimary))))
                else if (status == _DayStatus.closed)
                  Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: kColorSell.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: Text(_closedReason(sel, holiday), style: const TextStyle(color: kColorSell, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)))
                else ...[
                  // Show timing from API (or holiday special timing)
                  if (holidayTiming != null)
                    _timingPill(holidayTiming['start_time'], holidayTiming['end_time'], partial: true)
                  else if (exchangeTiming != null)
                    _timingPill(exchangeTiming['start_time'], exchangeTiming['end_time'])
                  else
                    const Text('Timing data not available', style: TextStyle(color: kColorTextMuted, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily)),
                ],
              ]),
            ),
            const SizedBox(height: 16),

            // Legend
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _legendDot(kColorBuy, 'Open'),
              const SizedBox(width: 16),
              _legendDot(const Color(0xFFF59E0B), 'Partial'),
              const SizedBox(width: 16),
              _legendDot(kColorSell, 'Closed'),
            ])),
            const SizedBox(height: 24),
          ]))),
      ])),
    );
  }

  Widget _timingPill(dynamic startEpoch, dynamic endEpoch, {bool partial = false}) {
    return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: partial ? const Color(0xFFF59E0B) : kColorBuy, borderRadius: BorderRadius.circular(12)),
      child: Text('${_formatEpoch(startEpoch)} - ${_formatEpoch(endEpoch)}', style: const TextStyle(color: Colors.white, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)));
  }

  Widget _statusBadge(_DayStatus s) {
    final (label, color) = switch (s) {
      _DayStatus.open => ('OPEN', kColorBuy),
      _DayStatus.partial => ('PARTIAL', const Color(0xFFF59E0B)),
      _DayStatus.closed => ('CLOSED', kColorSell),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightBold, letterSpacing: 0.5)));
  }

  String _dayLabel(DateTime d) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _closedReason(DateTime d, Map<String, dynamic>? holiday) {
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) return 'Weekend — Market closed';
    if (holiday != null) return '${holiday['description']} — Market closed';
    return 'Market closed';
  }

  Widget _legendDot(Color c, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
    ]);
  }
}

enum _DayStatus { open, partial, closed }
