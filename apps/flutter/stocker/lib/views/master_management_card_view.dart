import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../services/admin_service.dart';
import '../services/api_service.dart';
import '../utils/contants.dart';
import 'username_view.dart';

class MasterManagementCardView extends StatefulWidget {
  final Master master;

  const MasterManagementCardView({
    super.key,
    required this.master,
  });

  @override
  State<MasterManagementCardView> createState() =>
      _MasterManagementCardViewState();
}

class _MasterManagementCardViewState extends State<MasterManagementCardView> {
  late bool _isActive;
  List<Master> _childMasters = [];
  List<User> _users = [];
  bool _isLoadingChildren = true;
  late Master _currentMaster;

  @override
  void initState() {
    super.initState();
    _currentMaster = widget.master;
    _isActive = _currentMaster.activeStatus;
    _fetchChildrenData();
  }

  Future<void> _refreshMasterData() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      final response = await adminService.getMasterById(_currentMaster.id);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _currentMaster = Master.fromJson(data['data']);
            _isActive = _currentMaster.activeStatus;
          });
        }
      }
    } catch (e) {
      log('Error refreshing master data: $e');
    }
  }

  Future<void> _fetchChildrenData() async {
    setState(() {
      _isLoadingChildren = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      // Fetch child masters
      final mastersResponse = await adminService.getAllMasters(
        page: 1,
        limit: 100,
      );

      // Fetch users
      final usersResponse = await adminService.getAllUsers(
        page: 1,
        limit: 100,
      );

      if (mastersResponse.statusCode == 200) {
        final mastersData = jsonDecode(mastersResponse.body);
        if (mastersData['success'] == true) {
          final List<dynamic> mastersJson =
              mastersData['data']['masters'] ?? [];
          // Filter only child masters of this master
          _childMasters = mastersJson
              .map((json) {
                try {
                  return Master.fromJson(json);
                } catch (e) {
                  log('Error parsing child master: $e');
                  return null;
                }
              })
              .whereType<Master>()
              .where((m) => m.masterId == _currentMaster.id)
              .toList();
        }
      }

      if (usersResponse.statusCode == 200) {
        final usersData = jsonDecode(usersResponse.body);
        if (usersData['success'] == true) {
          final List<dynamic> usersJson = usersData['data']['users'] ?? [];
          // Filter only users of this master
          _users = usersJson
              .map((json) {
                try {
                  return User.fromJson(json);
                } catch (e) {
                  log('Error parsing user: $e');
                  return null;
                }
              })
              .whereType<User>()
              .where((u) => u.masterId == _currentMaster.id)
              .toList();
        }
      }
    } catch (e) {
      log('Error fetching children data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingChildren = false;
        });
      }
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child:
                        Icon(Icons.arrow_back, size: kIconSizeLarge, color: Colors.black),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentMaster.username,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeSectionHeader,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                UsernameView(master: widget.master)),
                      );

                      // If data was updated, refresh the master data
                      if (result == true && mounted) {
                        _refreshMasterData();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF3F45C7),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text(
                        'View Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: kFontSizeSubtitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Balance card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(10),
              decoration: ShapeDecoration(
                color: const Color(0xFFE5E5EA),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Credit: ${_currentMaster.credits.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeSectionHeader,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightRegular,
                    ),
                  ),
                  Text(
                    'Balance: ${_currentMaster.equity.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeSectionHeader,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightRegular,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Details card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Column(
                children: [
                  // Last Due Bill
                  _buildDetailRow(
                    'Last Due Bill',
                    _currentMaster.lastDueBill ?? 'N/A',
                    hasBorder: true,
                  ),

                  // Status
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                            width: 1, color: const Color(0xFFC7C7CC)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightRegular,
                          ),
                        ),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                final newStatus = !_isActive;

                                try {
                                  // Call API to update status
                                  final apiService = Provider.of<ApiService>(
                                      context,
                                      listen: false);
                                  final adminService = AdminService(apiService);

                                  final response =
                                      await adminService.updateMasterStatus(
                                    masterId: _currentMaster.id,
                                    activeStatus: newStatus,
                                  );

                                  if (response.statusCode == 200) {
                                    final data = jsonDecode(response.body);
                                    if (data['success'] == true) {
                                      setState(() {
                                        _isActive = newStatus;
                                      });
                                    }
                                  }
                                } catch (e) {
                                  log('Error updating status: $e');
                                }
                              },
                              child: Container(
                                width: 40,
                                height: 25,
                                padding: const EdgeInsets.all(2),
                                decoration: ShapeDecoration(
                                  color: _isActive
                                      ? const Color(0xFF3F45C7)
                                      : const Color(0xFFE5E5EA),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.5),
                                  ),
                                ),
                                child: Align(
                                  alignment: _isActive
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    width: 23,
                                    height: 23,
                                    decoration: ShapeDecoration(
                                      color: Colors.white,
                                      shape: OvalBorder(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              _isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: kFontSizeSectionHeader,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightRegular,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Credit
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Credit',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightRegular,
                          ),
                        ),
                        Text(
                          _currentMaster.credits.toStringAsFixed(2),
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeSectionHeader,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightRegular,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Child Masters and Users List
            Expanded(
              child: _isLoadingChildren
                  ? Center(
                      child: CircularProgressIndicator(
                          color: const Color(0xFF3F45C7)))
                  : (_childMasters.isEmpty && _users.isEmpty)
                      ? Center(
                          child: Text(
                            'No child masters or users',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: kFontSizeBody,
                              fontFamily: 'Inter',
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _childMasters.length + _users.length,
                          separatorBuilder: (context, index) =>
                              SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            if (index < _childMasters.length) {
                              // Render child master
                              final master = _childMasters[index];
                              return GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          UsernameView(master: master),
                                    ),
                                  );

                                  if (result == true) {
                                    _fetchChildrenData();
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
                                          size: kIconSizeLarge, color: Colors.black),
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
                                                    master.username
                                                        .toUpperCase(),
                                                    style: TextStyle(
                                                      color: Colors.black,
                                                      fontSize: kFontSizeBody,
                                                      fontFamily: 'Inter',
                                                      fontWeight:
                                                          kFontWeightRegular,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                SizedBox(width: 8),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 4,
                                                          vertical: 2),
                                                      decoration:
                                                          ShapeDecoration(
                                                        color: const Color(
                                                            0xFF007AFF),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4)),
                                                      ),
                                                      child: Text(
                                                        'MASTER',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: kFontSizeCaption,
                                                          fontFamily: 'Inter',
                                                          fontWeight:
                                                              kFontWeightMedium,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(width: 4),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 4,
                                                          vertical: 2),
                                                      decoration:
                                                          ShapeDecoration(
                                                        color:
                                                            master.activeStatus
                                                                ? const Color(
                                                                    0xFF34C759)
                                                                : const Color(
                                                                    0xFFFF3B30),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4)),
                                                      ),
                                                      child: Text(
                                                        master.activeStatus
                                                            ? 'ACTIVE'
                                                            : 'INACTIVE',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: kFontSizeCaption,
                                                          fontFamily: 'Inter',
                                                          fontWeight:
                                                              kFontWeightRegular,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.only(top: 6),
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
                                                      'BAL: ${master.equity.toStringAsFixed(2)}',
                                                      style: TextStyle(
                                                        color: const Color(
                                                            0xFF007AFF),
                                                        fontSize: kFontSizeNavLabel,
                                                        fontFamily: 'Inter',
                                                        fontWeight:
                                                            kFontWeightMedium,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      'P&L: ${master.pnlSharing.toStringAsFixed(0)}%',
                                                      style: TextStyle(
                                                        color: Colors.black,
                                                        fontSize: kFontSizeNavLabel,
                                                        fontFamily: 'Inter',
                                                        fontWeight:
                                                            kFontWeightMedium,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                            } else {
                              // Render user
                              final user = _users[index - _childMasters.length];
                              return GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          UsernameView(user: user),
                                    ),
                                  );

                                  if (result == true) {
                                    _fetchChildrenData();
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
                                          size: kIconSizeLarge, color: Colors.black),
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
                                                    user.username.toUpperCase(),
                                                    style: TextStyle(
                                                      color: Colors.black,
                                                      fontSize: kFontSizeBody,
                                                      fontFamily: 'Inter',
                                                      fontWeight:
                                                          kFontWeightRegular,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                SizedBox(width: 8),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 4,
                                                          vertical: 2),
                                                      decoration:
                                                          ShapeDecoration(
                                                        color: const Color(
                                                            0xFFFF9500),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4)),
                                                      ),
                                                      child: Text(
                                                        'USER',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: kFontSizeCaption,
                                                          fontFamily: 'Inter',
                                                          fontWeight:
                                                              kFontWeightMedium,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(width: 4),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 4,
                                                          vertical: 2),
                                                      decoration:
                                                          ShapeDecoration(
                                                        color: user.status ==
                                                                'active'
                                                            ? const Color(
                                                                0xFF34C759)
                                                            : const Color(
                                                                0xFFFF3B30),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4)),
                                                      ),
                                                      child: Text(
                                                        user.status == 'active'
                                                            ? 'ACTIVE'
                                                            : 'INACTIVE',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: kFontSizeCaption,
                                                          fontFamily: 'Inter',
                                                          fontWeight:
                                                              kFontWeightRegular,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.only(top: 6),
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
                                                      'BAL: ${user.equity.toStringAsFixed(2)}',
                                                      style: TextStyle(
                                                        color: const Color(
                                                            0xFF007AFF),
                                                        fontSize: kFontSizeNavLabel,
                                                        fontFamily: 'Inter',
                                                        fontWeight:
                                                            kFontWeightMedium,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      'P&L: ${user.pnlSharing.toStringAsFixed(0)}%',
                                                      style: TextStyle(
                                                        color: Colors.black,
                                                        fontSize: kFontSizeNavLabel,
                                                        fontFamily: 'Inter',
                                                        fontWeight:
                                                            kFontWeightMedium,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                            }
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool hasBorder = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: hasBorder
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
              ),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.black,
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightRegular,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.black,
              fontSize: kFontSizeSectionHeader,
              fontFamily: 'Inter',
              fontWeight: kFontWeightRegular,
            ),
          ),
        ],
      ),
    );
  }
}
