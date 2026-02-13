import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/option_chain.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/kite_service.dart';
import 'package:stocker/utils/contants.dart';

class OptionChainView extends StatefulWidget {
  final KiteInstrument instrument;

  const OptionChainView({super.key, required this.instrument});

  @override
  State<OptionChainView> createState() => _OptionChainViewState();
}

class _OptionChainViewState extends State<OptionChainView> {
  List<OptionChainItem> _optionChain = [];
  bool _isLoading = true;
  String? _error;
  String _selectedFilter = 'all';
  String _searchQuery = '';
  String? _currentExpiry;
  final TextEditingController _searchController = TextEditingController();
  Timer? _refreshTimer;
  late final KiteService _kiteService;

  @override
  void initState() {
    super.initState();
    _kiteService = KiteService(ApiService(backendUrl));
    _loadOptionChain();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshOptionChain();
    });
  }

  /// Silent refresh — no loading spinner, just updates prices in place
  Future<void> _refreshOptionChain() async {
    if (_isLoading || _optionChain.isEmpty) return;
    try {
      final baseSymbol = _extractBaseSymbol(
        _searchQuery.isEmpty ? widget.instrument.tradingsymbol : _searchQuery,
      );
      final chain = await _kiteService.getOptionChain(baseSymbol, expiry: _currentExpiry);
      if (mounted) {
        setState(() {
          _optionChain = chain;
        });
      }
    } catch (_) {
      // Silent fail — don't disrupt the UI on refresh errors
    }
  }

  Future<void> _loadOptionChain({String? expiry}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentExpiry = expiry;
    });

    try {
      final baseSymbol = _extractBaseSymbol(
        _searchQuery.isEmpty ? widget.instrument.tradingsymbol : _searchQuery,
      );
      
      final chain = await _kiteService.getOptionChain(baseSymbol, expiry: expiry);

      setState(() {
        _optionChain = chain;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _extractBaseSymbol(String tradingSymbol) {
    // Extract base symbol (e.g., "NIFTY" from "NIFTY2410050000CE")
    final match = RegExp(r'^([A-Z]+)').firstMatch(tradingSymbol);
    return match?.group(1) ?? tradingSymbol;
  }

  DateTime _getExpiryDate(String filter) {
    final now = DateTime.now();
    switch (filter) {
      case '7days':
        return now.add(Duration(days: 7));
      case '1month':
        return now.add(Duration(days: 30));
      case '3months':
        return now.add(Duration(days: 90));
      default:
        return now.add(Duration(days: 365)); // All
    }
  }

  void _onFilterChanged(String filter) {
    setState(() {
      _selectedFilter = filter;
    });

    if (filter == 'all') {
      _loadOptionChain();
    } else {
      final expiry = _getExpiryDate(filter);
      _loadOptionChain(expiry: expiry.toIso8601String().split('T')[0]);
    }
  }

  void _onSearch() {
    if (_searchQuery.isNotEmpty) {
      _loadOptionChain();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(17),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Option Chain',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Icon(Icons.close, color: Colors.black),
                ],
              ),
            ),

            // Stock selector with search
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 17),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 24, color: Colors.black),
                  SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: _extractBaseSymbol(widget.instrument.tradingsymbol),
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      onSubmitted: (_) => _onSearch(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, size: 20, color: const Color(0xFF22547C)),
                    onPressed: _onSearch,
                  ),
                ],
              ),
            ),

            SizedBox(height: 12),

            // Time period filters
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterChip('All', _selectedFilter == 'all', () => _onFilterChanged('all')),
                  SizedBox(width: 10),
                  _buildFilterChip('Last 7 Days', _selectedFilter == '7days', () => _onFilterChanged('7days')),
                  SizedBox(width: 10),
                  _buildFilterChip('1 Month', _selectedFilter == '1month', () => _onFilterChanged('1month')),
                  SizedBox(width: 10),
                  _buildFilterChip('3 Months', _selectedFilter == '3months', () => _onFilterChanged('3months')),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Table header
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'CALL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFF8E8E93),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'STRIKE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFF8E8E93),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'PUT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFF8E8E93),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Table data
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red),
                                SizedBox(height: 16),
                                Text('Failed to load option chain', style: TextStyle(color: Colors.red)),
                                SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: () => _loadOptionChain(),
                                  child: Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : _optionChain.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.search_off, size: 48, color: Colors.grey),
                                    SizedBox(height: 16),
                                    Text(
                                      'No option chain data available',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _optionChain.length,
                                itemBuilder: (context, index) {
                                  final item = _optionChain[index];
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border(
                                        bottom: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            child: Column(
                                              children: [
                                                Text(
                                                  item.call?.lastPrice.toStringAsFixed(2) ?? '--',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (item.call != null)
                                                  Text(
                                                    item.call!.changePercent,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: const Color(0xFF34C759),
                                                      fontSize: 12,
                                                      fontFamily: 'Inter',
                                                      fontWeight: FontWeight.w400,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF7F8FC),
                                            ),
                                            child: Text(
                                              item.strike.toStringAsFixed(0),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 16,
                                                fontFamily: 'Inter',
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            child: Column(
                                              children: [
                                                Text(
                                                  item.put?.lastPrice.toStringAsFixed(2) ?? '--',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (item.put != null)
                                                  Text(
                                                    item.put!.changePercent,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: const Color(0xFFFF3B30),
                                                      fontSize: 12,
                                                      fontFamily: 'Inter',
                                                      fontWeight: FontWeight.w400,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: ShapeDecoration(
            color: isSelected ? const Color(0x33ABABAB) : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? const Color(0xFF22547C) : Colors.black,
              fontSize: 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
