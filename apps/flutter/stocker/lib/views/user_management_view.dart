import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../providers/user_profile_provider.dart';
import 'create_user_view.dart';
import 'create_master_view.dart';
import 'username_view.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({super.key});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  List<Master> _masters = [];
  List<User> _users = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);

      if (profileProvider.isAdmin) {
        // Admin: Fetch all masters and users
        final mastersResponse = await adminService.getAllMasters(limit: 100);
        final usersResponse = await adminService.getAllUsers(limit: 100);

        if (mastersResponse.statusCode == 200 &&
            usersResponse.statusCode == 200) {
          final mastersData = jsonDecode(mastersResponse.body);
          final usersData = jsonDecode(usersResponse.body);

          if (mastersData['success'] == true && usersData['success'] == true) {
            setState(() {
              _masters = (mastersData['data']['masters'] as List)
                  .map((json) => Master.fromJson(json))
                  .toList();
              _users = (usersData['data']['users'] as List)
                  .map((json) => User.fromJson(json))
                  .toList();
              _isLoading = false;
            });
            log('✅ Admin loaded ${_masters.length} masters and ${_users.length} users');
          } else {
            setState(() {
              _error = 'Failed to load data';
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _error = 'Failed to load data';
            _isLoading = false;
          });
        }
      } else {
        // Master: Fetch only child masters and users
        final mastersResponse = await adminService.getChildMasters(limit: 100);
        final usersResponse = await adminService.getChildUsers(limit: 100);

        if (mastersResponse.statusCode == 200 &&
            usersResponse.statusCode == 200) {
          final mastersData = jsonDecode(mastersResponse.body);
          final usersData = jsonDecode(usersResponse.body);

          if (mastersData['success'] == true && usersData['success'] == true) {
            setState(() {
              _masters = (mastersData['data']['masters'] as List)
                  .map((json) => Master.fromJson(json))
                  .toList();
              _users = (usersData['data']['users'] as List)
                  .map((json) => User.fromJson(json))
                  .toList();
              _isLoading = false;
            });
            log('✅ Master loaded ${_masters.length} child masters and ${_users.length} child users');
          } else {
            setState(() {
              _error = 'Failed to load data';
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _error = 'Failed to load data';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      log('❌ Error fetching data: $e');
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filteredItems {
    final allItems = <dynamic>[..._masters, ..._users];

    if (_searchQuery.isEmpty) {
      return allItems;
    }

    return allItems.where((item) {
      final username = item is Master ? item.username : (item as User).username;
      final name = item is Master ? item.name : (item as User).name;
      return username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          name.toLowerCase().contains(_searchQuery.toLowerCase());
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
                      Consumer<UserProfileProvider>(
                        builder: (context, profileProvider, child) {
                          return Text(
                            profileProvider.isAdmin
                                ? 'Master and User Management'
                                : 'User Management',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
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
                        Icon(Icons.search,
                            size: 24, color: const Color(0xFF8E8E93)),
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
                              hintText: 'Search users',
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
                  Icon(Icons.filter_list,
                      size: 24, color: const Color(0xFF8E8E93)),
                ],
              ),
            ),

            SizedBox(height: 16),

            // User list
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_error!,
                                  style: TextStyle(color: Colors.red)),
                              SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _fetchData,
                                child: Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _filteredItems.isEmpty
                          ? Center(
                              child: Text(
                                _searchQuery.isEmpty
                                    ? 'No users or masters found'
                                    : 'No results found',
                                style: TextStyle(
                                  color: const Color(0xFF8E8E93),
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _filteredItems.length,
                              separatorBuilder: (context, index) =>
                                  SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final item = _filteredItems[index];
                                final isMaster = item is Master;
                                final username = isMaster
                                    ? item.username
                                    : (item as User).username;
                                final balance = isMaster
                                    ? item.balance
                                    : (item as User).balance;
                                final pnlSharing = isMaster
                                    ? item.pnlSharing
                                    : (item as User).pnlSharing;
                                final isActive = isMaster
                                    ? item.activeStatus
                                    : (item as User).status == 'active';

                                return GestureDetector(
                                  onTap: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UsernameView(
                                          master: isMaster ? item : null,
                                          user: isMaster ? null : item,
                                        ),
                                      ),
                                    );

                                    // Refresh data if changes were made
                                    if (result == true) {
                                      _fetchData();
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
                                        Icon(Icons.person,
                                            size: 24, color: Colors.black),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      username.toUpperCase(),
                                                      style: TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 14,
                                                        fontFamily: 'Inter',
                                                        fontWeight:
                                                            FontWeight.w400,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 4,
                                                                vertical: 2),
                                                        decoration:
                                                            ShapeDecoration(
                                                          color: isMaster
                                                              ? const Color(
                                                                  0xFF007AFF)
                                                              : const Color(
                                                                  0xFFFF9500),
                                                          shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4)),
                                                        ),
                                                        child: Text(
                                                          isMaster
                                                              ? 'MASTER'
                                                              : 'USER',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(width: 4),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 4,
                                                                vertical: 2),
                                                        decoration:
                                                            ShapeDecoration(
                                                          color: isActive
                                                              ? const Color(
                                                                  0xFF34C759)
                                                              : const Color(
                                                                  0xFFFF3B30),
                                                          shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4)),
                                                        ),
                                                        child: Text(
                                                          isActive
                                                              ? 'ACTIVE'
                                                              : 'INACTIVE',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w400,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.only(
                                                    top: 6),
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(
                                                        width: 1,
                                                        color: const Color(
                                                            0xFFD1D1D6)),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        'BAL: ${balance.toStringAsFixed(2)}',
                                                        style: TextStyle(
                                                          color: const Color(
                                                              0xFF007AFF),
                                                          fontSize: 11,
                                                          fontFamily: 'Inter',
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        'P&L: ${pnlSharing.toStringAsFixed(0)}%',
                                                        style: TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 11,
                                                          fontFamily: 'Inter',
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
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

            // Create user button
            GestureDetector(
              onTap: () {
                _showCreateOptionsBottomSheet(context);
              },
              child: Container(
                margin: const EdgeInsets.all(16),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: ShapeDecoration(
                  color: const Color(0xFF22547C),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  'CREATE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateOptionsBottomSheet(BuildContext context) {
    final profileProvider =
        Provider.of<UserProfileProvider>(context, listen: false);
    final isAdmin = profileProvider.isAdmin;
    final isMaster = profileProvider.isMaster;
    final canAddMaster = profileProvider.canAddMaster;

    // Debug logging
    log('🔍 Bottom sheet debug:');
    log('   isAdmin: $isAdmin');
    log('   isMaster: $isMaster');
    log('   canAddMaster: $canAddMaster');
    log('   role: ${profileProvider.role}');
    log('   master: ${profileProvider.master?.username}');
    log('   master.addMaster: ${profileProvider.master?.addMaster}');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D1D6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(height: 20),

              // Title
              const Text(
                'Create New',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 20),

              // Create Master Option
              // Show for: Admin (always) OR Master with add_master=true
              if (isAdmin || (isMaster && canAddMaster))
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateMasterView(),
                      ),
                    ).then((result) {
                      if (result == true) {
                        _fetchData();
                      }
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFF7F8FC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const ShapeDecoration(
                            color: Color(0xFF007AFF),
                            shape: OvalBorder(),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Master',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Create a new master account',
                                style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Color(0xFF8E8E93),
                        ),
                      ],
                    ),
                  ),
                ),

              if (isAdmin || (isMaster && canAddMaster))
                const SizedBox(height: 12),

              // Create User Option
              // Show for: Master (always, including those with add_master=true)
              // Hide for: Admin (admins can only create masters)
              if (isMaster)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateUserView(),
                      ),
                    ).then((result) {
                      if (result == true) {
                        _fetchData();
                      }
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFF7F8FC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const ShapeDecoration(
                            color: Color(0xFFFF9500),
                            shape: OvalBorder(),
                          ),
                          child: const Icon(
                            Icons.person_add,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create User',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Create a new user account',
                                style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Color(0xFF8E8E93),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // Cancel Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: ShapeDecoration(
                    color: const Color(0xFFD1D1D6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
