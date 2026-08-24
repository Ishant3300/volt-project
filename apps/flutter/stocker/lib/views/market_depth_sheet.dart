import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stocker/models/market_depth.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/kite_service.dart';
import 'package:stocker/utils/contants.dart';

class MarketDepthSheet extends StatefulWidget {
  final String instrumentToken;

  const MarketDepthSheet({super.key, required this.instrumentToken});

  @override
  State<MarketDepthSheet> createState() => _MarketDepthSheetState();
}

class _MarketDepthSheetState extends State<MarketDepthSheet> {
  MarketDepth? _marketDepth;
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;
  late final KiteService _kiteService;

  @override
  void initState() {
    super.initState();
    _kiteService = KiteService(ApiService(backendUrl));
    _loadMarketDepth();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshMarketDepth();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Silent refresh — updates data without showing loading spinner
  Future<void> _refreshMarketDepth() async {
    if (_isLoading || _marketDepth == null) return;
    try {
      final depth = await _kiteService.getMarketDepth(widget.instrumentToken);
      if (mounted && depth != null) {
        setState(() {
          _marketDepth = depth;
        });
      }
    } catch (_) {
      // Silent fail on refresh
    }
  }

  Future<void> _loadMarketDepth() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final depth = await _kiteService.getMarketDepth(widget.instrumentToken);

      setState(() {
        _marketDepth = depth;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: ShapeDecoration(
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
          SizedBox(height: 24),
          Text(
            'Market Depth',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: kFontSizeSheetTitle,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),
          SizedBox(height: 16),

          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Failed to load market depth',
                    style: TextStyle(color: Colors.red),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadMarketDepth,
                    child: Text('Retry'),
                  ),
                ],
              ),
            )
          else if (_marketDepth != null && _marketDepth!.ohlc != null)
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildOHLCSection(),
                      SizedBox(height: 16),
                      if (_marketDepth!.lastPrice != null)
                        _buildPriceSection(),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No market depth data available',
                style: TextStyle(color: Colors.grey),
              ),
            ),

          SizedBox(height: 16),
          // Close button
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: ShapeDecoration(
                  color: const Color(0xFFD1D1D6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  'CLOSE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: kFontSizeButtonText,
                    fontFamily: kFontFamily,
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

  Widget _buildOHLCSection() {
    final ohlc = _marketDepth!.ohlc!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OHLC Data',
          style: TextStyle(
            color: Colors.black,
            fontSize: kFontSizeBody,
            fontFamily: kFontFamily,
            fontWeight: kFontWeightSemiBold,
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            _buildOHLCCard('OPEN', ohlc.open.toStringAsFixed(2)),
            SizedBox(width: 8),
            _buildOHLCCard('HIGH', ohlc.high.toStringAsFixed(2)),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            _buildOHLCCard('LOW', ohlc.low.toStringAsFixed(2)),
            SizedBox(width: 8),
            _buildOHLCCard('CLOSE', ohlc.close.toStringAsFixed(2)),
          ],
        ),
      ],
    );
  }

  Widget _buildOHLCCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ShapeDecoration(
          color: const Color(0xFFF7F8FC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: const Color(0xFF8E8E93),
                fontSize: kFontSizeSheetLabel,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightRegular,
              ),
            ),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: Colors.black,
                fontSize: kFontSizeSectionHeader,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightSemiBold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: const Color(0xFFF7F8FC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Last Price',
            style: TextStyle(
              color: const Color(0xFF8E8E93),
              fontSize: kFontSizeBody,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightRegular,
            ),
          ),
          Text(
            _marketDepth!.lastPrice!.toStringAsFixed(2),
            style: TextStyle(
              color: Colors.black,
              fontSize: kFontSizeViewTitle,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),
        ],
      ),
    );
  }
}

void showMarketDepthSheet(BuildContext context, String instrumentToken) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => MarketDepthSheet(instrumentToken: instrumentToken),
  );
}
