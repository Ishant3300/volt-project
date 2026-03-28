import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer';
import '../providers/user_profile_provider.dart';
import '../services/admin_service.dart';
import '../models/user.dart';
import '../utils/contants.dart';

class CreateUserView extends StatefulWidget {
  final User? user;

  const CreateUserView({super.key, this.user});

  @override
  State<CreateUserView> createState() => _CreateUserViewState();
}

class _CreateUserViewState extends State<CreateUserView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _creditController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _marginSquareOff = false;
  bool _changePasswordOnFirstLogin = true;
  bool _isSubmitting = false;

  Map<String, Map<String, dynamic>> _exchangeSettings = {};
  Map<String, bool> _tradeLimit = {};
  Map<String, List<String>> _exchangeLotNames = {};

  List<String> _allowedExchanges = [];
  List<String> _allowedTradeLimit = [];

  @override
  void initState() {
    super.initState();
    _loadMasterPermissions();

    if (widget.user != null) {
      _nameController.text = widget.user!.name;
      _usernameController.text = widget.user!.username;
      _creditController.text = widget.user!.credits.toString();
      _noteController.text = widget.user!.note;
      _marginSquareOff = widget.user!.marginSquareOff;
      _changePasswordOnFirstLogin = widget.user!.changePassOnFirstLogin;
    }
  }

  void _loadMasterPermissions() async {
    final profileProvider =
        Provider.of<UserProfileProvider>(context, listen: false);
    final adminService = Provider.of<AdminService>(context, listen: false);

    if (profileProvider.master != null) {
      setState(() {
        _allowedExchanges = profileProvider.master!.exchangesAllowed
            .map((ex) => ex == 'INDICES' ? 'GLOBAL' : ex)
            .toList();
        _allowedTradeLimit = profileProvider.master!.tradeLimit
            .map((ex) => ex == 'INDICES' ? 'GLOBAL' : ex)
            .toList();

        _exchangeSettings = {};
        for (var exchange in _allowedExchanges) {
          _exchangeSettings[exchange] = {
            'enabled': false,
            'turnover': false,
            'lot': false,
            'group': null,
          };
        }

        if (widget.user != null) {
          for (var userExchange in widget.user!.exchangesAllowed) {
            // Backend stores INDICES, but UI uses GLOBAL
            final displayName = userExchange.exchangeName == 'INDICES'
                ? 'GLOBAL'
                : userExchange.exchangeName;
            if (_exchangeSettings.containsKey(displayName)) {
              _exchangeSettings[displayName] = {
                'enabled': true,
                'turnover': userExchange.turnover,
                'lot': userExchange.lot,
                'group': userExchange.groupName.isNotEmpty
                    ? userExchange.groupName
                    : null,
              };
            }
          }
        }

        _tradeLimit = {};
        for (var exchange in _allowedTradeLimit) {
          // Backend stores INDICES, but UI uses GLOBAL — map for comparison
          final backendName = exchange == 'GLOBAL' ? 'INDICES' : exchange;
          _tradeLimit[exchange] =
              widget.user?.tradeLimit.contains(backendName) ?? false;
        }
      });

      for (var exchange in _allowedExchanges) {
        _fetchLotNamesForExchange(exchange, adminService);
      }
    }
  }

  Future<void> _fetchLotNamesForExchange(
      String exchange, AdminService adminService) async {
    final String apiExchange = exchange == 'GLOBAL' ? 'INDICES' : exchange;
    try {
      final response = await adminService.getLotNamesByExchange(apiExchange);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _exchangeLotNames[exchange] = List<String>.from(data['data']);
          });
        }
      }
    } catch (e) {
      log('❌ Error fetching lot names for $exchange: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _creditController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      ),
    );
  }

  Future<void> _createUser() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('Please enter name', isError: true);
      return;
    }
    if (_usernameController.text.trim().isEmpty) {
      _showSnack('Please enter username', isError: true);
      return;
    }

    if (widget.user == null) {
      if (_passwordController.text.isEmpty) {
        _showSnack('Please enter password', isError: true);
        return;
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        _showSnack('Passwords do not match', isError: true);
        return;
      }
    } else {
      if (_passwordController.text.isNotEmpty &&
          _passwordController.text != _confirmPasswordController.text) {
        _showSnack('Passwords do not match', isError: true);
        return;
      }
    }

    if (_creditController.text.trim().isEmpty) {
      _showSnack('Please enter credit amount', isError: true);
      return;
    }
    final credit = double.tryParse(_creditController.text.trim());
    if (credit == null || credit < 0) {
      _showSnack('Please enter a valid credit amount', isError: true);
      return;
    }

    final profileProvider =
        Provider.of<UserProfileProvider>(context, listen: false);
    if (profileProvider.master == null) {
      _showSnack('Master profile not found', isError: true);
      return;
    }

    List<Map<String, dynamic>> exchangesAllowed = [];
    _exchangeSettings.forEach((exchange, settings) {
      if (settings['enabled'] == true) {
        exchangesAllowed.add({
          'exchange_name': exchange.toUpperCase(),
          'turnover': settings['turnover'] ?? false,
          'lot': settings['lot'] ?? false,
          'group_name': settings['group'] ?? '',
        });
      }
    });

    if (exchangesAllowed.isEmpty) {
      _showSnack('Please select at least one exchange', isError: true);
      return;
    }

    List<String> tradeLimitList = [];
    _tradeLimit.forEach((exchange, enabled) {
      if (enabled) tradeLimitList.add(exchange.toUpperCase());
    });

    setState(() => _isSubmitting = true);

    try {
      final adminService = Provider.of<AdminService>(context, listen: false);
      http.Response response;

      if (widget.user != null) {
        response = await adminService.updateUser(
          userId: widget.user!.id,
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          credits: credit,
          note: _noteController.text.trim().isEmpty
              ? ''
              : _noteController.text.trim(),
          pnlSharing: profileProvider.master!.pnlSharing,
          brokerageSharing: profileProvider.master!.brokerageSharing,
          exchangesAllowed: exchangesAllowed,
          tradeLimit: tradeLimitList,
          marginSquareOff: _marginSquareOff,
          changePassOnFirstLogin: _changePasswordOnFirstLogin,
        );
      } else {
        response = await adminService.createUser(
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          credits: credit,
          note: _noteController.text.trim().isEmpty
              ? ''
              : _noteController.text.trim(),
          pnlSharing: profileProvider.master!.pnlSharing,
          brokerageSharing: profileProvider.master!.brokerageSharing,
          exchangesAllowed: exchangesAllowed,
          tradeLimit: tradeLimitList,
          marginSquareOff: _marginSquareOff,
          changePassOnFirstLogin: _changePasswordOnFirstLogin,
          serverId: profileProvider.master!.serverId,
        );
      }

      if (!mounted) return;
      final data = jsonDecode(response.body);

      if ((response.statusCode == 201 || response.statusCode == 200) &&
          data['success'] == true) {
        await profileProvider.refreshProfile();
        if (!mounted) return;
        _showSnack(widget.user != null
            ? 'User updated successfully'
            : 'User created successfully');
        Navigator.pop(context, true);
      } else {
        _showSnack(data['message'] ?? 'Failed', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      width: 40,
                      height: 40,
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
                      child: const Icon(Icons.arrow_back,
                          color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.user != null ? 'Edit User' : 'Create User',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeViewTitle,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('PERSONAL DETAILS'),
                    const SizedBox(height: 12),
                    _card(
                      child: Column(
                        children: [
                          _buildTextField(
                              label: 'Name', controller: _nameController),
                          _divider(),
                          _buildTextField(
                              label: 'Username',
                              controller: _usernameController),
                          _divider(),
                          _buildTextField(
                              label: 'Password',
                              controller: _passwordController,
                              obscureText: true),
                          _divider(),
                          _buildTextField(
                              label: 'Confirm',
                              controller: _confirmPasswordController,
                              obscureText: true),
                          _divider(),
                          _buildTextField(
                              label: 'Credit',
                              controller: _creditController,
                              keyboardType: TextInputType.number),
                          _divider(),
                          _buildTextField(
                              label: 'Note', controller: _noteController),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Exchange Allow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionLabel('EXCHANGE ALLOW'),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              final all = _exchangeSettings.values
                                  .every((v) => v['enabled']);
                              _exchangeSettings
                                  .forEach((k, v) => v['enabled'] = !all);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3F45C7)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _exchangeSettings.values
                                      .every((v) => v['enabled'])
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: const TextStyle(
                                  color: Color(0xFF3F45C7),
                                  fontSize: kFontSizeNavLabel,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightSemiBold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_exchangeSettings.isEmpty)
                      _card(
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No exchanges available',
                                style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: kFontSizeBodySmall,
                                    fontFamily: 'Inter')),
                          ),
                        ),
                      )
                    else
                      _card(
                        child: Column(
                          children: [
                            // Header
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: const [
                                  Expanded(
                                      flex: 2,
                                      child: Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Text('Exchange',
                                              style: TextStyle(
                                                  color: Color(0xFF94A3B8),
                                                  fontSize: kFontSizeNavLabel,
                                                  fontFamily: 'Inter',
                                                  fontWeight: kFontWeightSemiBold,
                                                  letterSpacing: 0.5)))),
                                  Expanded(
                                      flex: 1,
                                      child: Center(
                                          child: Text('T/O',
                                              style: TextStyle(
                                                  color: Color(0xFF94A3B8),
                                                  fontSize: kFontSizeNavLabel,
                                                  fontFamily: 'Inter',
                                                  fontWeight: kFontWeightSemiBold,
                                                  letterSpacing: 0.5)))),
                                  Expanded(
                                      flex: 1,
                                      child: Center(
                                          child: Text('Lot',
                                              style: TextStyle(
                                                  color: Color(0xFF94A3B8),
                                                  fontSize: kFontSizeNavLabel,
                                                  fontFamily: 'Inter',
                                                  fontWeight: kFontWeightSemiBold,
                                                  letterSpacing: 0.5)))),
                                  SizedBox(
                                      width: 130,
                                      child: Center(
                                          child: Text('Group',
                                              style: TextStyle(
                                                  color: Color(0xFF94A3B8),
                                                  fontSize: kFontSizeNavLabel,
                                                  fontFamily: 'Inter',
                                                  fontWeight: kFontWeightSemiBold,
                                                  letterSpacing: 0.5)))),
                                ],
                              ),
                            ),
                            ..._exchangeSettings.entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child:
                                    _buildExchangeRow(entry.key, entry.value),
                              );
                            }),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Trade Limit
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionLabel('HIGH LOW BETWEEN TRADE LIMIT'),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              final all = _tradeLimit.values.every((v) => v);
                              _tradeLimit.updateAll((k, v) => !all);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3F45C7)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _tradeLimit.values.every((v) => v)
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: const TextStyle(
                                  color: Color(0xFF3F45C7),
                                  fontSize: kFontSizeNavLabel,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightSemiBold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_tradeLimit.isEmpty)
                      _card(
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No trade limits available',
                                style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: kFontSizeBodySmall,
                                    fontFamily: 'Inter')),
                          ),
                        ),
                      )
                    else
                      _card(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _tradeLimit.keys.map((key) {
                            final selected = _tradeLimit[key]!;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _tradeLimit[key] = !selected),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFF3F45C7)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: selected
                                          ? const Color(0xFF3F45C7)
                                          : const Color(0xFFF1F5F9)),
                                ),
                                child: Text(
                                  key,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF64748B),
                                    fontSize: kFontSizeBodySmall,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Toggles
                    _card(
                      child: Column(
                        children: [
                          _buildToggleRow('Margin Square Off', _marginSquareOff,
                              (v) => setState(() => _marginSquareOff = v)),
                          if (widget.user == null) ...[
                            _divider(),
                            _buildToggleRow(
                                'Change password on first login',
                                _changePasswordOnFirstLogin,
                                (v) => setState(
                                    () => _changePasswordOnFirstLogin = v)),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Submit
                    GestureDetector(
                      onTap: _isSubmitting ? null : _createUser,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: _isSubmitting
                              ? null
                              : const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Color(0xFFC6529E),
                                    Color(0xFF3B43C9),
                                  ],
                                ),
                          color: _isSubmitting ? const Color(0xFF94A3B8) : null,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(
                                  widget.user != null
                                      ? 'UPDATE USER'
                                      : 'CREATE USER',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: kFontSizeButtonText,
                                      fontFamily: 'Inter',
                                      fontWeight: kFontWeightSemiBold,
                                      letterSpacing: 0.3),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared widgets ──

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: kFontSizeNavLabel,
        fontFamily: 'Inter',
        fontWeight: kFontWeightSemiBold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: kFontSizeBodySmall,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightMedium),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: kFontSizeBody,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightMedium),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: label,
                hintStyle: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: kFontSizeBody,
                    fontFamily: 'Inter'),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeRow(String exchange, Map<String, dynamic> settings) {
    final enabled = settings['enabled'] as bool;
    final ex = exchange.toUpperCase();

    // NFO-FUT, SGX, GLOBAL → block Lot checkbox (turnover-only exchanges)
    final bool lotBlocked = ex == 'NFO-FUT' || ex == 'SGX' || ex == 'GLOBAL';
    // NFO-OPT, MCX-OPT, MCX-FUT → block T/O checkbox (lot-only exchanges)
    final bool toBlocked = ex == 'NFO-OPT' || ex == 'MCX-OPT' || ex == 'MCX-FUT';

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () => setState(() => settings['enabled'] = !enabled),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color:
                        enabled ? const Color(0xFF3F45C7) : Colors.transparent,
                    border: Border.all(
                        color: enabled
                            ? const Color(0xFF3F45C7)
                            : const Color(0xFFCBD5E1),
                        width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: enabled
                      ? const Icon(Icons.check, color: Colors.white, size: kIconSizeSmall)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(exchange,
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: kFontSizeBodySmall,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: GestureDetector(
            onTap: toBlocked
                ? null
                : () => setState(() =>
                    settings['turnover'] = !(settings['turnover'] as bool)),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: toBlocked
                      ? const Color(0xFFE2E8F0)
                      : (settings['turnover'] as bool)
                          ? const Color(0xFF3F45C7)
                          : Colors.transparent,
                  border: Border.all(
                      color: toBlocked
                          ? const Color(0xFFE2E8F0)
                          : (settings['turnover'] as bool)
                              ? const Color(0xFF3F45C7)
                              : const Color(0xFFCBD5E1),
                      width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: (settings['turnover'] as bool) && !toBlocked
                    ? const Icon(Icons.check, color: Colors.white, size: kIconSizeSmall)
                    : null,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: GestureDetector(
            onTap: lotBlocked
                ? null
                : () => setState(
                    () => settings['lot'] = !(settings['lot'] as bool)),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: lotBlocked
                      ? const Color(0xFFE2E8F0)
                      : (settings['lot'] as bool)
                          ? const Color(0xFF3F45C7)
                          : Colors.transparent,
                  border: Border.all(
                      color: lotBlocked
                          ? const Color(0xFFE2E8F0)
                          : (settings['lot'] as bool)
                              ? const Color(0xFF3F45C7)
                              : const Color(0xFFCBD5E1),
                      width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: (settings['lot'] as bool) && !lotBlocked
                    ? const Icon(Icons.check, color: Colors.white, size: kIconSizeSmall)
                    : null,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 130,
          height: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: settings['group'] as String?,
                hint: Text(
                  _exchangeLotNames[exchange]?.isEmpty ?? true
                      ? 'None'
                      : 'Select',
                  style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: kFontSizeSubtitle,
                      fontFamily: 'Inter'),
                ),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down,
                    size: kIconSizeDefault, color: Color(0xFF94A3B8)),
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: kFontSizeSubtitle,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightMedium),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                onChanged: (_exchangeLotNames[exchange]?.isEmpty ?? true)
                    ? null
                    : (value) => setState(() => settings['group'] = value),
                items: (_exchangeLotNames[exchange] ?? []).map((name) {
                  return DropdownMenuItem<String>(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis));
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: kFontSizeBody,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightMedium)),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color:
                    value ? const Color(0xFF3F45C7) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
