import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/contants.dart';

class TradeFilterResult {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? exchange;
  final String? tradingsymbol;

  TradeFilterResult({this.dateFrom, this.dateTo, this.exchange, this.tradingsymbol});

  bool get hasActiveFilters =>
      dateFrom != null || dateTo != null || exchange != null || (tradingsymbol != null && tradingsymbol!.isNotEmpty);

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (dateFrom != null) params['date_from'] = dateFrom!.toIso8601String();
    if (dateTo != null) params['date_to'] = dateTo!.toIso8601String();
    if (exchange != null) params['exchange'] = exchange!;
    if (tradingsymbol != null && tradingsymbol!.isNotEmpty) params['tradingsymbol'] = tradingsymbol!;
    return params;
  }
}

class PortfolioFilterSheet extends StatefulWidget {
  final TradeFilterResult? currentFilters;
  const PortfolioFilterSheet({super.key, this.currentFilters});

  @override
  State<PortfolioFilterSheet> createState() => _PortfolioFilterSheetState();
}

class _PortfolioFilterSheetState extends State<PortfolioFilterSheet> {
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _exchange;
  final TextEditingController _scriptController = TextEditingController();

  static const List<String> _exchanges = [
    'NSE', 'BSE', 'NFO', 'BFO', 'MCX', 'CDS', 'NSEIX', 'GLOBAL'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.currentFilters != null) {
      _dateFrom = widget.currentFilters!.dateFrom;
      _dateTo = widget.currentFilters!.dateTo;
      _exchange = widget.currentFilters!.exchange;
      _scriptController.text = widget.currentFilters!.tradingsymbol ?? '';
    }
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: kBrandPrimary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _exchange = null;
      _scriptController.clear();
    });
  }

  void _applyFilters() {
    final result = TradeFilterResult(
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      exchange: _exchange,
      tradingsymbol: _scriptController.text.trim().isEmpty ? null : _scriptController.text.trim(),
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 56),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filter Trades', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                  GestureDetector(
                    onTap: _clearFilters,
                    child: const Text('Clear All', style: TextStyle(color: kBrandPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Script name search
              const Text('Script Name', style: TextStyle(color: Color(0xFF2B2B2B), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
              const SizedBox(height: 8),
              TextField(
                controller: _scriptController,
                decoration: InputDecoration(
                  hintText: 'e.g. NIFTY, RELIANCE',
                  hintStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeBody, fontFamily: kFontFamily),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93), size: kIconSizeMedium),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC7C7CC))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC7C7CC))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBrandPrimary)),
                ),
                style: const TextStyle(fontSize: kFontSizeBody, fontFamily: kFontFamily),
              ),
              const SizedBox(height: 16),

              // Date range
              Row(
                children: [
                  Expanded(child: _buildDateField('From', _dateFrom, dateFormat, () => _pickDate(true))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildDateField('To', _dateTo, dateFormat, () => _pickDate(false))),
                ],
              ),
              const SizedBox(height: 16),

              // Exchange
              const Text('Exchange', style: TextStyle(color: Color(0xFF2B2B2B), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
              const SizedBox(height: 8),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD1D1D6)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _exchange,
                    isExpanded: true,
                    hint: const Text('All Exchanges', style: TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeBody, fontFamily: kFontFamily)),
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('All Exchanges', style: TextStyle(fontSize: kFontSizeBody, fontFamily: kFontFamily))),
                      ..._exchanges.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: kFontSizeBody, fontFamily: kFontFamily)))),
                    ],
                    onChanged: (val) => setState(() => _exchange = val),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(8)),
                        child: const Text('CLOSE', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: _applyFilters,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(8)),
                        child: const Text('SEARCH', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateField(String label, DateTime? date, DateFormat fmt, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF2B2B2B), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFC7C7CC)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date != null ? fmt.format(date) : 'DD/MM/YYYY',
                  style: TextStyle(color: date != null ? Colors.black : const Color(0xFF8E8E93), fontSize: kFontSizeBody, fontFamily: kFontFamily),
                ),
                const Icon(Icons.calendar_today, size: kFontSizeViewTitle, color: Color(0xFF222222)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

void showPortfolioFilterSheet(BuildContext context, {TradeFilterResult? currentFilters, required ValueChanged<TradeFilterResult?> onApply}) {
  showModalBottomSheet<TradeFilterResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => PortfolioFilterSheet(currentFilters: currentFilters),
  ).then((result) {
    if (result != null) {
      onApply(result);
    }
  });
}
