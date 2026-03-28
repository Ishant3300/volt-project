import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:interactive_chart/interactive_chart.dart';
import 'package:intl/intl.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/chart_service.dart';
import 'package:stocker/utils/contants.dart';

class ChartView extends StatefulWidget {
  final KiteInstrument instrument;

  const ChartView({
    super.key,
    required this.instrument,
  });

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  List<CandleData> _candles = [];
  bool _isLoading = true;
  String _selectedInterval = '5minute';
  int _selectedDays = 7;
  
  final Map<String, String> _intervals = {
    '1 Min': 'minute',
    '3 Min': '3minute',
    '5 Min': '5minute',
    '15 Min': '15minute',
    '30 Min': '30minute',
    '1 Hour': '60minute',
    'Day': 'day',
  };

  final Map<String, int> _timeRanges = {
    '1D': 1,
    '5D': 5,
    '1W': 7,
    '1M': 30,
    '3M': 90,
    '6M': 180,
    '1Y': 365,
  };

  late ChartService _chartService;

  @override
  void initState() {
    super.initState();
    final apiService = ApiService(backendUrl);
    _chartService = ChartService(apiService);
    _loadChartData();
  }

  Future<void> _loadChartData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final toDate = DateTime.now();
      final fromDate = toDate.subtract(Duration(days: _selectedDays));
      
      final dateFormat = DateFormat('yyyy-MM-dd');
      final fromDateStr = dateFormat.format(fromDate);
      final toDateStr = dateFormat.format(toDate);

      log('📊 Loading chart data for ${widget.instrument.tradingsymbol}');
      log('   Token: ${widget.instrument.instrumentToken}');
      log('   Interval: $_selectedInterval');
      log('   From: $fromDateStr, To: $toDateStr');

      final data = await _chartService.getHistoricalData(
        instrumentToken: widget.instrument.instrumentToken,
        interval: _selectedInterval,
        fromDate: fromDateStr,
        toDate: toDateStr,
      );

      if (data.isEmpty) {
        log('⚠️  No candle data received');
        setState(() {
          _candles = [];
          _isLoading = false;
        });
        return;
      }

      // Convert to CandleData objects for interactive_chart
      final candles = data.map((item) {
        try {
          // Parse date - handle both string and DateTime
          DateTime date;
          if (item['date'] is String) {
            date = DateTime.parse(item['date']);
          } else if (item['date'] is DateTime) {
            date = item['date'];
          } else {
            date = DateTime.now();
          }

          // Parse numeric values safely
          double parseSafe(dynamic value) {
            if (value == null) return 0.0;
            if (value is int) return value.toDouble();
            if (value is double) {
              if (value.isNaN || value.isInfinite) return 0.0;
              return value;
            }
            try {
              return double.parse(value.toString());
            } catch (e) {
              return 0.0;
            }
          }

          final open = parseSafe(item['open']);
          final high = parseSafe(item['high']);
          final low = parseSafe(item['low']);
          final close = parseSafe(item['close']);
          final volume = parseSafe(item['volume']);

          // Skip invalid candles
          if (open <= 0 || high <= 0 || low <= 0 || close <= 0) {
            return null;
          }

          // Ensure logical consistency
          final actualHigh = [open, high, low, close].reduce((a, b) => a > b ? a : b);
          final actualLow = [open, high, low, close].reduce((a, b) => a < b ? a : b);

          if (actualHigh <= 0 || actualLow <= 0 || actualHigh < actualLow) {
            return null;
          }

          return CandleData(
            timestamp: date.millisecondsSinceEpoch,
            open: open,
            high: actualHigh,
            low: actualLow,
            close: close,
            volume: volume.abs(),
          );
        } catch (e) {
          log('❌ Error parsing candle: $e');
          return null;
        }
      }).whereType<CandleData>().toList();

      log('✅ Loaded ${candles.length} valid candles');

      setState(() {
        _candles = candles;
        _isLoading = false;
      });
    } catch (e) {
      log('❌ Error loading chart data: $e');
      setState(() {
        _candles = [];
        _isLoading = false;
      });
    }
  }

  void _changeInterval(String displayName) {
    final interval = _intervals[displayName];
    if (interval != null && interval != _selectedInterval) {
      setState(() {
        _selectedInterval = interval;
      });
      _loadChartData();
    }
  }

  void _changeTimeRange(String displayName) {
    final days = _timeRanges[displayName];
    if (days != null && days != _selectedDays) {
      setState(() {
        _selectedDays = days;
      });
      _loadChartData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.instrument.name.isNotEmpty
                  ? widget.instrument.name.toUpperCase()
                  : widget.instrument.tradingsymbol,
              style: const TextStyle(
                color: Colors.black,
                fontSize: kFontSizeViewTitle,
                fontFamily: 'Inter',
                fontWeight: kFontWeightSemiBold,
              ),
            ),
            if (widget.instrument.expiry != null)
              Text(
                widget.instrument.expiryDisplay,
                style: const TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _loadChartData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Interval selector
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _intervals.keys.map((displayName) {
                  final isSelected = _intervals[displayName] == _selectedInterval;
                  return GestureDetector(
                    onTap: () => _changeInterval(displayName),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF3F45C7)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontSize: kFontSizeBody,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Time range selector
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _timeRanges.keys.map((displayName) {
                final isSelected = _timeRanges[displayName] == _selectedDays;
                return GestureDetector(
                  onTap: () => _changeTimeRange(displayName),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF3F45C7)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      displayName,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontSize: kFontSizeSubtitle,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // Chart
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _candles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.show_chart,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No chart data available',
                                style: TextStyle(
                                  fontSize: kFontSizeSectionHeader,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try a different time range or interval',
                                style: TextStyle(
                                  fontSize: kFontSizeBody,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : InteractiveChart(
                          candles: _candles,
                          style: ChartStyle(
                            priceGainColor: const Color(0xFF34C759),
                            priceLossColor: const Color(0xFFFF3B30),
                            volumeColor: Colors.grey.withOpacity(0.5),
                            trendLineStyles: [
                              Paint()
                                ..strokeWidth = 2.0
                                ..strokeCap = StrokeCap.round
                                ..color = const Color(0xFF3F45C7),
                            ],
                            priceGridLineColor: Colors.grey.withOpacity(0.2),
                            priceLabelStyle: const TextStyle(
                              color: Colors.black87,
                              fontSize: kFontSizeSubtitle,
                            ),
                            timeLabelStyle: const TextStyle(
                              color: Colors.black87,
                              fontSize: kFontSizeSubtitle,
                            ),
                          ),
                        ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
