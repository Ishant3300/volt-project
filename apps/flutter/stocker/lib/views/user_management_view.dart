import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../providers/user_profile_provider.dart';
import '../utils/contants.dart';
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    if (_searchQuery.isEmpty) return allItems;

    return allItems.where((item) {
      final username = item is Master ? item.username : (item as User).username;
      final name = item is Master ? item.name : (item as User).name;
      return username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = Provider.of<UserProfileProvider>(context);
    final title =
        profileProvider.isAdmin ? 'Master & User Management' : 'User Management';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: kIconSizeDefault, color: Color(0xFF475569)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeSectionHeader,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  // Count badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_filteredItems.length}',
                      style: const TextStyle(
                        color: Color(0xFF3F45C7),
                        fontSize: kFontSizeBodySmall,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightBold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search,
                        color: Color(0xFF94A3B8), size: kIconSizeMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: kFontSizeBody,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search users or masters',
                          hintStyle: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightRegular,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: const Icon(Icons.close,
                            color: Color(0xFF94A3B8), size: kIconSizeMedium),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Summary row
            if (!_isLoading && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildCountChip(
                        'Masters', _masters.length, const Color(0xFF3F45C7)),
                    const SizedBox(width: 8),
                    _buildCountChip(
                        'Users', _users.length, const Color(0xFFD97706)),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF3F45C7),
                        strokeWidth: 2.5,
                      ),
                    )
                  : _error != null
                      ? _buildErrorState()
                      : _filteredItems.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: _fetchData,
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.02),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: _filteredItems.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    color: Color(0xFFF1F5F9),
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = _filteredItems[index];
                                    if (item is Master) {
                                      return _buildMasterRow(item);
                                    } else {
                                      return _buildUserRow(item as User);
                                    }
                                  },
                                ),
                              ),
                            ),
            ),

            // Create button
            Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () => _showCreateSheet(context),
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFC6529E),
                        Color(0xFF3B43C9),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3F45C7).withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: kIconSizeMedium),
                      SizedBox(width: 8),
                      Text(
                        'Create',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: kFontSizeButtonText,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: kFontSizeSubtitle,
              fontFamily: 'Inter',
              fontWeight: kFontWeightBold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: kFontSizeSubtitle,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.error_outline,
                size: kIconSizeXLarge, color: Color(0xFFEF4444)),
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Something went wrong',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _fetchData,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF3F45C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: kFontSizeBody,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightSemiBold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.people_outline,
                size: kIconSizeXLarge, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'No users or masters found'
                : 'No results for "$_searchQuery"',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterRow(Master master) {
    final bool isActive = master.activeStatus;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UsernameView(master: master, user: null),
          ),
        );
        if (result == true) _fetchData();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  master.name.isNotEmpty
                      ? master.name[0].toUpperCase()
                      : 'M',
                  style: const TextStyle(
                    color: Color(0xFF3F45C7),
                    fontSize: kFontSizeSectionHeader,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightBold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          master.username.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeName,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightName,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3F45C7).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'MASTER',
                          style: TextStyle(
                            color: Color(0xFF3F45C7),
                            fontSize: kFontSizeBadge,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightBold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Credits: ${master.credits.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeNavLabel,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: kFontSizeCaption, color: Color(0xFFCBD5E1))),
                      ),
                      Text(
                        'P&L: ${master.pnlSharing.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeNavLabel,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: kIconSizeMedium, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildUserRow(User user) {
    final bool isActive = user.status == 'active';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UsernameView(master: null, user: user),
          ),
        );
        if (result == true) _fetchData();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Color(0xFFD97706),
                    fontSize: kFontSizeSectionHeader,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightBold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeName,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightName,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'USER',
                          style: TextStyle(
                            color: Color(0xFFD97706),
                            fontSize: kFontSizeBadge,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightBold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Credits: ${user.credits.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeNavLabel,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: kFontSizeCaption, color: Color(0xFFCBD5E1))),
                      ),
                      Text(
                        'P&L: ${user.pnlSharing.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeNavLabel,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: kIconSizeMedium, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    final profileProvider =
        Provider.of<UserProfileProvider>(context, listen: false);
    final isAdmin = profileProvider.isAdmin;
    final isMaster = profileProvider.isMaster;
    final canAddMaster = profileProvider.canAddMaster;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Create New',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: kFontSizeSectionHeader,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightSemiBold,
                  ),
                ),
                const SizedBox(height: 16),

                // Create Master
                if (isAdmin || (isMaster && canAddMaster))
                  _buildCreateOption(
                    icon: Icons.admin_panel_settings,
                    iconColor: const Color(0xFF3F45C7),
                    title: 'Create Master',
                    subtitle: 'Create a new master account',
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateMasterView(),
                        ),
                      ).then((result) {
                        if (result == true) _fetchData();
                      });
                    },
                  ),

                // Create User
                if (isMaster)
                  _buildCreateOption(
                    icon: Icons.person_add,
                    iconColor: const Color(0xFFD97706),
                    title: 'Create User',
                    subtitle: 'Create a new user account',
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateUserView(),
                        ),
                      ).then((result) {
                        if (result == true) _fetchData();
                      });
                    },
                  ),

                const SizedBox(height: 8),

                // Cancel
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontSize: kFontSizeButtonText,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightSemiBold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: kIconSizeLarge),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeBody,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: kFontSizeSubtitle,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightRegular,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: kIconSizeMedium, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}
