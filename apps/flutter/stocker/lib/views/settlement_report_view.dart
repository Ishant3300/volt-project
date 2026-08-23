import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class SettlementReportView extends StatefulWidget {
  final Master? master;
  final User? user;

  const SettlementReportView({super.key, this.master, this.user});

  @override
  State<SettlementReportView> createState() => _SettlementReportViewState();
}

class _SettlementReportViewState extends State<SettlementReportView> {
  int _selectedTabIndex = 0; // 0 = Profit, 1 = Loss
  bool _isLoading = false;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _reportData = [];

  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final token = await _storage.getToken();
      final apiService = ApiService(backendUrl);
      final role = await _storage.getRole();
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final params = <String>['date=$dateStr'];
      if (role == 'ADMIN' && widget.master != null) {
        params.add('master_id=${widget.master!.id}');
      } else if (role == 'ADMIN' && widget.user != null) {
        params.add('user_id=${widget.user!.id}');
      } else if (role == 'MASTER' && widget.user != null) {
        params.add('user_id=${widget.user!.id}');
      }

      final url = '/master/settlement-report?${params.join('&')}';
      final response = await apiService.get(url, token: token);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          setState(() {
            _reportData = List<Map<String, dynamic>>.from(body['data'] ?? []);
            _isLoading = false;
          });
        } else {
          setState(() { _error = body['message'] ?? 'Failed'; _isLoading = false; });
        }
      } else {
        setState(() { _error = 'Failed to load report'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Error: $e'; _isLoading = false; });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: kBrandPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchReport();
    }
  }

  List<Map<String, dynamic>> get _filteredData {
    if (_selectedTabIndex == 0) {
      return _reportData.where((d) => (d['pnl'] as num? ?? 0) >= 0).toList();
    } else {
      return _reportData.where((d) => (d['pnl'] as num? ?? 0) < 0).toList();
    }
  }

  String get _title {
    if (widget.user != null) return '${widget.user!.username} - Settlement';
    if (widget.master != null) return '${widget.master!.username} - Settlement';
    return 'Settlement Report';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredData;
    final double totalPnl = filtered.fold(
        0.0, (s, d) => s + ((d['pnl'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeViewTitle,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Date Picker
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 48,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC7C7CC)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('dd/MM/yyyy').format(_selectedDate),
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: kFontSizeBody,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightRegular,
                      ),
                    ),
                    const Icon(Icons.calendar_today,
                        size: kIconSizeMedium, color: Color(0xFF222222)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Position Summary
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Position',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeBody,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightRegular,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: totalPnl >= 0
                          ? const Color(0x3334C759)
                          : const Color(0x33FF3B30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'P&L: ${totalPnl.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: totalPnl >= 0
                            ? const Color(0xFF34C759)
                            : const Color(0xFFFF3B30),
                        fontSize: kFontSizeBody,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Tab buttons
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildTabButton('Profit', 0, isLeft: true),
                  _buildTabButton('Loss', 1, isLeft: false),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Table Header
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const Row(
                children: [
                  Expanded(
                      child: Text('USERNAME',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: kFontSizeCaption,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium))),
                  Expanded(
                      child: Text('P&L',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: kFontSizeCaption,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium))),
                  Expanded(
                      child: Text('BRK',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: kFontSizeCaption,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium))),
                  Expanded(
                      child: Text('TOTAL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: kFontSizeCaption,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium))),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Table Data
            Expanded(child: _buildTableContent(filtered)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index, {required bool isLeft}) {
    final selected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: ShapeDecoration(
            color: selected ? kBrandPrimary : Colors.white,
            shape: RoundedRectangleBorder(
              side:
                  const BorderSide(width: 1, color: kBrandPrimary),
              borderRadius: BorderRadius.only(
                topLeft:
                    isLeft ? const Radius.circular(8) : Radius.zero,
                bottomLeft:
                    isLeft ? const Radius.circular(8) : Radius.zero,
                topRight:
                    !isLeft ? const Radius.circular(8) : Radius.zero,
                bottomRight:
                    !isLeft ? const Radius.circular(8) : Radius.zero,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  selected ? Colors.white : const Color(0xFF333333),
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableContent(List<Map<String, dynamic>> filtered) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: kBrandPrimary));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: kFontSizeBody,
                    fontFamily: 'Inter')),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _fetchReport,
              child: const Text('Retry',
                  style: TextStyle(
                      color: kBrandPrimary,
                      fontSize: kFontSizeBody,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold)),
            ),
          ],
        ),
      );
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _selectedTabIndex == 0
              ? 'No profit entries'
              : 'No loss entries',
          style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: kFontSizeBody,
              fontFamily: 'Inter'),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFFD1D1D6)),
        itemBuilder: (context, index) {
          final d = filtered[index];
          final pnl = (d['pnl'] as num?)?.toDouble() ?? 0;
          final brk = (d['brokerage'] as num?)?.toDouble() ?? 0;
          final total = (d['total'] as num?)?.toDouble() ?? 0;
          final username = d['username'] ?? '';

          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(username,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: kFontSizeBody,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightName)),
                ),
                Expanded(
                  child: Text(pnl.toStringAsFixed(2),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: pnl >= 0
                              ? const Color(0xFF34C759)
                              : const Color(0xFFFF3B30),
                          fontSize: kFontSizeBody,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular)),
                ),
                Expanded(
                  child: Text(brk.toStringAsFixed(2),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: kFontSizeBody,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular)),
                ),
                Expanded(
                  child: Text(total.toStringAsFixed(2),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: total >= 0
                              ? const Color(0xFF34C759)
                              : const Color(0xFFFF3B30),
                          fontSize: kFontSizeBody,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
