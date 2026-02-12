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
  bool _isSearching = false;
  String? _selectedExchange;
  String? _selectedType;

  final List<String> _exchanges = ['NFO', 'BFO', 'MCX'];
  final List<String> _types = ['FUT', 'CE', 'PE'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    print('🔍 Search triggered with query: "$query"');
    
    if (query.isEmpty) {
      print('   Query is empty, clearing results');
      setState(() {
        _searchResults = [];
      });
      return;
    }

    print('   Setting isSearching = true');
    setState(() {
      _isSearching = true;
    });

    try {
      print('   Getting KiteService from provider...');
      final kiteService = Provider.of<KiteService>(context, listen: false);
      
      print('   Calling searchInstruments...');
      print('   - Query: $query');
      print('   - Exchange: $_selectedExchange');
      print('   - Type: $_selectedType');
      
      final results = await kiteService.searchInstruments(
        query: query,
        exchange: _selectedExchange,
        instrumentType: _selectedType,
      );

      print('   ✅ Search completed');
      print('   Found ${results.length} results');

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
      
      print('   State updated with results');
    } catch (e, stackTrace) {
      print('   ❌ Search error: $e');
      print('   Stack trace: $stackTrace');
      
      setState(() {
        _isSearching = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _addToWatchlist(KiteInstrument instrument) {
    print('➕ Adding to watchlist: ${instrument.tradingsymbol}');
    
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    
    if (watchlistProvider.contains(instrument.instrumentToken)) {
      print('   ⚠️ Already in watchlist');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already in watchlist'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    watchlistProvider.addInstrument(instrument);
    print('   ✅ Added to watchlist');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${instrument.tradingsymbol} added to watchlist'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
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
        title: const Text(
          'Search Instruments',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by symbol (e.g., NIFTY, BANKNIFTY)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _performSearch('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    _performSearch(value);
                  },
                ),
                const SizedBox(height: 12),
                // Filters
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedExchange,
                        decoration: InputDecoration(
                          labelText: 'Exchange',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All'),
                          ),
                          ..._exchanges.map((exchange) => DropdownMenuItem(
                                value: exchange,
                                child: Text(exchange),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedExchange = value;
                          });
                          if (_searchController.text.isNotEmpty) {
                            _performSearch(_searchController.text);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All'),
                          ),
                          ..._types.map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedType = value;
                          });
                          if (_searchController.text.isNotEmpty) {
                            _performSearch(_searchController.text);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'Search for instruments'
                                  : 'No results found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final instrument = _searchResults[index];
                          final watchlistProvider = Provider.of<WatchlistProvider>(context);
                          final isInWatchlist = watchlistProvider.contains(instrument.instrumentToken);

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              title: Text(
                                instrument.tradingsymbol,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${instrument.exchange} • ${instrument.instrumentType}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (instrument.expiry != null)
                                    Text(
                                      'Expiry: ${instrument.expiryDisplay}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                              trailing: isInWatchlist
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.add_circle_outline),
                                      onPressed: () => _addToWatchlist(instrument),
                                    ),
                              onTap: () => _addToWatchlist(instrument),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
