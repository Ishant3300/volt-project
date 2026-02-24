import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../services/admin_service.dart';
import '../services/api_service.dart';
import 'master_management_card_view.dart';

class MasterManagementView extends StatefulWidget {
  const MasterManagementView({super.key});

  @override
  State<MasterManagementView> createState() => _MasterManagementViewState();
}

class _MasterManagementViewState extends State<MasterManagementView> {
  List<Master> _masters = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  int _currentPage = 1;
  final int _limit = 100;

  @override
  void initState() {
    super.initState();
    _fetchMasters();
  }

  Future<void> _fetchMasters({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      final response = await adminService.getAllMasters(
        page: loadMore ? _currentPage + 1 : 1,
        limit: _limit,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final List<dynamic> mastersJson = data['data']['masters'] ?? [];
          
          final List<Master> fetchedMasters = [];
          for (var i = 0; i < mastersJson.length; i++) {
            try {
              final master = Master.fromJson(mastersJson[i]);
              fetchedMasters.add(master);
            } catch (e, stackTrace) {
              log('❌ Error parsing master at index $i: $e');
              log('Master JSON: ${jsonEncode(mastersJson[i])}');
              log('Stack trace: $stackTrace');
            }
          }

          setState(() {
            if (loadMore) {
              _masters.addAll(fetchedMasters);
              _currentPage++;
            } else {
              _masters = fetchedMasters;
              _currentPage = 1;
            }
            _isLoading = false;
          });
          log('✅ Loaded ${fetchedMasters.length} masters');
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to load masters';
            _isLoading = false;
          });
        }
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _errorMessage = data['message'] ?? 'Failed to load masters';
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      log('❌ Error in _fetchMasters: $e');
      log('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  List<Master> get _filteredMasters {
    if (_searchQuery.isEmpty) {
      return _masters;
    }
    
    return _masters.where((master) {
      return master.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             master.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
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
                        'Master Management',
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

            // Search bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 24, color: const Color(0xFF8E8E93)),
                        SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Search masters',
                              hintStyle: TextStyle(
                                color: const Color(0xFF8E8E93),
                                fontSize: 16,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.filter_list, size: 24, color: const Color(0xFF8E8E93)),
                ],
              ),
            ),

            SizedBox(height: 16),

            // List of masters
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_errorMessage!, style: TextStyle(color: Colors.red)),
                              SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _fetchMasters,
                                child: Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _filteredMasters.isEmpty
                          ? Center(
                              child: Text(
                                _searchQuery.isEmpty ? 'No masters found' : 'No results found',
                                style: TextStyle(
                                  color: const Color(0xFF8E8E93),
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _filteredMasters.length,
                              separatorBuilder: (context, index) => SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final master = _filteredMasters[index];
                                
                                return GestureDetector(
                                  onTap: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => MasterManagementCardView(master: master),
                                      ),
                                    );
                                    
                                    // Refresh data if changes were made
                                    if (result == true) {
                                      _fetchMasters();
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: ShapeDecoration(
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.person, size: 24, color: Colors.black),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      master.username.toUpperCase(),
                                                      style: TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 14,
                                                        fontFamily: 'Inter',
                                                        fontWeight: FontWeight.w400,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                        decoration: ShapeDecoration(
                                                          color: const Color(0xFF007AFF),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                        ),
                                                        child: Text(
                                                          'MASTER',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontFamily: 'Inter',
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(width: 4),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                        decoration: ShapeDecoration(
                                                          color: master.activeStatus ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                        ),
                                                        child: Text(
                                                          master.activeStatus ? 'ACTIVE' : 'INACTIVE',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontFamily: 'Inter',
                                                            fontWeight: FontWeight.w400,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.only(top: 6),
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        'CREDIT: ${master.credits.toStringAsFixed(2)}',
                                                        style: TextStyle(
                                                          color: const Color(0xFF007AFF),
                                                          fontSize: 11,
                                                          fontFamily: 'Inter',
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        'P&L: ${master.pnlSharing.toStringAsFixed(0)}%',
                                                        style: TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 11,
                                                          fontFamily: 'Inter',
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
