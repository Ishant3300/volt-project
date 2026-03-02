import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/services/kite_service.dart';

class InstrumentSearchPage extends StatefulWidget {
  const InstrumentSearchPage({super.key});

  @override
  State<InstrumentSearchPage> createState() => _InstrumentSearchPageState();
}

class _InstrumentSearchPageState extends State<InstrumentSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<KiteInstrument> _searchResults = [];
  final Map<String, KiteInstrument> _selectedInstruments = {};
  bool _isSearching = false;
  String _activeTab = 'ALL';

  final List<String> _tabs = [
    'ALL',
    'NSE',
    'CALLPUT',
    'MCX',
    'MCX-OPT',
    'OTHERS'
  ];

  // Colors based on Stitch design
  final Color primaryColor = const Color(0xFF254b7a);
  final Color backgroundColor = const Color(0xFFFFFFFF);
  final Color surfaceColor = const Color(0xFFF8F9FA);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final kiteService = Provider.of<KiteService>(context, listen: false);

      String? exchange;
      if (_activeTab == 'NSE') {
        exchange = 'NSE';
      } else if (_activeTab == 'MCX' || _activeTab == 'MCX-OPT') {
        exchange = 'MCX'; // Simplification, backend handles detailed routing
      } else if (_activeTab == 'CALLPUT') {
        exchange = 'NFO'; // Assuming NSE Derivatives for Call/Put
      }

      final results = await kiteService.searchInstruments(
        query,
        exchange: exchange,
        limit: 50,
      );

      final instruments = results
          .map((json) => KiteInstrument.fromJson(json))
          .where((instrument) {
        if (_activeTab == 'CALLPUT') {
          return instrument.instrumentType == 'CE' ||
              instrument.instrumentType == 'PE';
        }
        return true;
      }).toList();

      setState(() {
        _searchResults = instruments;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Search failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _saveSelected() {
    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);
    int addedCount = 0;

    for (var instrument in _selectedInstruments.values) {
      if (!watchlistProvider.contains(instrument.instrumentToken)) {
        watchlistProvider.addInstrument(instrument);
        addedCount++;
      }
    }

    if (addedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$addedCount instruments added to watchlist'),
          backgroundColor: Colors.green,
        ),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header: Search Input and SAVE Button
            Padding(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, top: 16, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC), // slate-50 equivalent
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Color(0xFF94A3B8)), // slate-400
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF0F172A),
                                  fontFamily: 'Inter'),
                              decoration: const InputDecoration(
                                hintText: 'Search eg: NSE, CALL PUT, MCX',
                                hintStyle: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 14,
                                    fontFamily: 'Inter'),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 14),
                              ),
                              onChanged: (value) => _performSearch(value),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Color(0xFF94A3B8), size: 20),
                              onPressed: () {
                                _searchController.clear();
                                _performSearch('');
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed:
                        _selectedInstruments.isEmpty ? null : _saveSelected,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      disabledBackgroundColor: primaryColor.withOpacity(0.5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('SAVE',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            fontFamily: 'Inter')),
                  ),
                ],
              ),
            ),

            // Horizontal Filter Tabs
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: _tabs.map((tab) => _buildTab(tab)).toList(),
                ),
              ),
            ),

            // Search Results List
            Expanded(
              child: Stack(
                children: [
                  _isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : _searchResults.isEmpty
                          ? Center(
                              child: Text(
                                _searchController.text.isEmpty
                                    ? 'Search for instruments'
                                    : 'No results found',
                                style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 14,
                                    fontFamily: 'Inter'),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(
                                  bottom: 80), // Space for floating counter
                              itemCount: _searchResults.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                      height: 1, color: Color(0xFFE2E8F0)),
                              itemBuilder: (context, index) {
                                final instrument = _searchResults[index];
                                final isSelected = _selectedInstruments
                                    .containsKey(instrument.instrumentToken);

                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedInstruments
                                            .remove(instrument.instrumentToken);
                                      } else {
                                        _selectedInstruments[instrument
                                            .instrumentToken] = instrument;
                                      }
                                    });
                                  },
                                  child: Container(
                                    color: isSelected
                                        ? const Color(0xFFF8FAFC)
                                        : Colors.white,
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Left Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                                0xFFF1F5F9), // slate-100
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            instrument.exchange,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(
                                                  0xFF475569), // slate-600
                                              fontFamily: 'Inter',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // Middle Content
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      instrument.tradingsymbol,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 14,
                                                        color: Color(
                                                            0xFF0F172A), // slate-900
                                                        fontFamily: 'Inter',
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (instrument.expiryDisplay
                                                      .isNotEmpty) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      decoration:
                                                          const BoxDecoration(
                                                        color: Color(
                                                            0xFFCBD5E1), // slate-300
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      instrument.expiryDisplay,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: Color(
                                                            0xFF0F172A), // slate-900
                                                        fontFamily: 'Inter',
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Text(
                                                    'MAX: 0', // Placeholder from design
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: Color(
                                                            0xFF64748B), // slate-500
                                                        fontFamily: 'Inter'),
                                                  ),
                                                  const Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 8),
                                                    child: Text('|',
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: Color(
                                                                0xFFCBD5E1))),
                                                  ),
                                                  const Text(
                                                    'BREAKUP: 0', // Placeholder
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color:
                                                            Color(0xFF64748B),
                                                        fontFamily: 'Inter'),
                                                  ),
                                                  const Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 8),
                                                    child: Text('|',
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: Color(
                                                                0xFFCBD5E1))),
                                                  ),
                                                  Text(
                                                    'LOTSIZE: ${instrument.lotSize}',
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        color:
                                                            Color(0xFF64748B),
                                                        fontFamily: 'Inter'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Right Checkbox
                                        Container(
                                          width: 24,
                                          height: 24,
                                          margin: const EdgeInsets.only(top: 4),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected
                                                  ? primaryColor
                                                  : const Color(0xFFCBD5E1),
                                              width: 2,
                                            ),
                                            color: isSelected
                                                ? primaryColor
                                                : Colors.transparent,
                                          ),
                                          child: isSelected
                                              ? const Icon(Icons.check,
                                                  size: 16, color: Colors.white)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                  // Floating Result Counter Pill
                  if (_searchResults.isNotEmpty)
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1)
                                .withOpacity(0.9), // slate-300
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Text(
                            'RESULT: ${_searchResults.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B), // slate-800
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title) {
    final isActive = _activeTab == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = title;
        });
        if (_searchController.text.isNotEmpty) {
          _performSearch(_searchController.text);
        }
      },
      child: Container(
        padding: const EdgeInsets.only(bottom: 12, right: 24),
        decoration: BoxDecoration(
          border: isActive
              ? const Border(
                  bottom: BorderSide(
                      color: Color(0xFF0F172A), width: 2)) // slate-900
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive
                ? const Color(0xFF0F172A)
                : const Color(0xFF64748B), // slate-900 / slate-500
          ),
        ),
      ),
    );
  }
}
