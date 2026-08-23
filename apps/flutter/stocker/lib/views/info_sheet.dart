import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class InfoSheet extends StatefulWidget {
  final String instrumentToken;
  final String tradingsymbol;
  final int? lotSize;
  final int? maxQty;
  final int? breakQty;
  final String? groupName;

  const InfoSheet({
    super.key,
    required this.instrumentToken,
    required this.tradingsymbol,
    this.lotSize,
    this.maxQty,
    this.breakQty,
    this.groupName,
  });

  @override
  State<InfoSheet> createState() => _InfoSheetState();
}

class _InfoSheetState extends State<InfoSheet> {
  bool _isLoading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchInfo();
  }

  Future<void> _fetchInfo() async {
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).get(
        '/trade/instrument-info?token=${widget.instrumentToken}',
        token: token,
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() => _data = body['data']);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  String _formatExpiry(String? expiry) {
    if (expiry == null) return 'N/A';
    try {
      final dt = DateTime.parse(expiry);
      return DateFormat('dd MMM yyyy').format(dt).toUpperCase();
    } catch (_) {
      return expiry;
    }
  }

  String _formatBrokerage(Map<String, dynamic>? brk) {
    if (brk == null) return 'N/A';
    final value = brk['value'];
    final type = brk['type'] ?? '';
    if (type == 'TURNOVER WISE') return '$value (Turnover)';
    if (type == 'LOT WISE') return '$value (Per Lot)';
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Instrument Info',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: kFontSizeSheetTitle,
              fontFamily: 'Inter',
              fontWeight: kFontWeightSemiBold,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildInfoRow('Script', _data?['script'] ?? widget.tradingsymbol, false),
                    _buildInfoRow('Segment', _data?['segment'] ?? 'N/A', true),
                    _buildInfoRow('Exchange', _data?['exchange'] ?? 'N/A', false),
                    _buildInfoRow('Expiry', _formatExpiry(_data?['expiry']?.toString()), true),
                    _buildInfoRow('Lot Size', '${_data?['lot_size'] ?? widget.lotSize ?? 'N/A'}', false),
                    _buildInfoRow('Tick Size', '${_data?['tick_size'] ?? 'N/A'}', true),
                    _buildInfoRow('Type', _data?['instrument_type'] ?? 'N/A', false),
                    if (widget.maxQty != null && widget.maxQty! > 0)
                      _buildInfoRow('Max Qty', '${widget.maxQty}', true),
                    if (widget.breakQty != null && widget.breakQty! > 0)
                      _buildInfoRow('Break Qty', '${widget.breakQty}', false),
                    if (widget.groupName != null && widget.groupName!.isNotEmpty)
                      _buildInfoRow('Group', widget.groupName!, true),
                    _buildInfoRow('Brokerage', _formatBrokerage(_data?['brokerage']), false),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: ShapeDecoration(
                  color: const Color(0xFFD1D1D6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'CLOSE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: kFontSizeButtonText,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightSemiBold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isGray) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isGray ? const Color(0xFFF2F2F7) : Colors.white,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: kFontSizeSheetBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.black,
                fontSize: kFontSizeSheetBody,
                fontFamily: 'Inter',
                fontWeight: kFontWeightSemiBold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

void showInfoSheet(BuildContext context, {
  required String instrumentToken,
  required String tradingsymbol,
  int? lotSize,
  int? maxQty,
  int? breakQty,
  String? groupName,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => InfoSheet(
      instrumentToken: instrumentToken,
      tradingsymbol: tradingsymbol,
      lotSize: lotSize,
      maxQty: maxQty,
      breakQty: breakQty,
      groupName: groupName,
    ),
  );
}
