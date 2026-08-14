import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/number_to_words.dart';
import '../models/master.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../providers/user_profile_provider.dart';
import '../utils/contants.dart';
import '../utils/wallet_category.dart';

class CreateMasterView extends StatefulWidget {
  final Master? master;

  const CreateMasterView({super.key, this.master});

  @override
  State<CreateMasterView> createState() => _CreateMasterViewState();
}

class _CreateMasterViewState extends State<CreateMasterView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _creditController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _profitLossController = TextEditingController();
  final TextEditingController _brkSharingController = TextEditingController();

  bool _addMaster = false;
  bool _changePasswordOnFirstLogin = true;
  bool _isSubmitting = false;
  String? _selectedServerId;
  List<Map<String, dynamic>> _servers = [];
  bool _isLoadingServers = false;
  String? _generatedUsername;
  bool _isSuccess = false;

  Map<String, bool> _exchangeAllow = {
    'NFO-FUT': false,
    'NFO-OPT': false,
    'MCX-FUT': false,
    'MCX-OPT': false,
    'SGX': false,
    'GLOBAL': false,
  };

  Map<String, bool> _highLowBetweenTradeLimit = {
    'NFO-FUT': false,
    'NFO-OPT': false,
    'MCX-FUT': false,
    'MCX-OPT': false,
    'SGX': false,
    'GLOBAL': false,
  };

  // Trade Wallet inputs per allowed category (NSE/MCX/GLOBAL)
  final Map<String, TextEditingController> _walletControllers = {};

  @override
  void dispose() {
    if (!_isSuccess) _releaseUsername();
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _creditController.dispose();
    _noteController.dispose();
    _profitLossController.dispose();
    _brkSharingController.dispose();
    for (final controller in _walletControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Exchange/segment names currently selected in the form (for exchanges_allowed).
  List<String> get _selectedExchangeNames =>
      _exchangeAllow.entries.where((e) => e.value).map((e) => e.key).toList();

  /// Reuse (or lazily create) a controller for a wallet category.
  TextEditingController _walletControllerFor(String category) =>
      _walletControllers.putIfAbsent(category, () => TextEditingController());

  /// Build the wallet funding map from parsed inputs (> 0) for allowed categories.
  Map<String, double> _buildWalletMap(List<String> allowedCats) {
    final Map<String, double> wallet = {};
    for (final cat in allowedCats) {
      final controller = _walletControllers[cat];
      if (controller == null) continue;
      final amount = double.tryParse(controller.text.trim());
      if (amount != null && amount > 0) wallet[cat] = amount;
    }
    return wallet;
  }

  void _generateUsername() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final res = await adminService.generateUsername();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        setState(() {
          _generatedUsername = data['username'];
          _usernameController.text = _generatedUsername!;
        });
      }
    } catch (e) {
      log('Error generating username: $e');
    }
  }

  void _releaseUsername() async {
    if (_generatedUsername != null) {
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final adminService = AdminService(apiService);
        await adminService.releaseUsername(_generatedUsername!);
      } catch (e) {
        log('Error releasing username: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchServers();
    if (widget.master == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _generateUsername());
    }

    _profitLossController.addListener(() => setState(() {}));
    _brkSharingController.addListener(() => setState(() {}));

    if (widget.master != null) {
      final master = widget.master!;
      _nameController.text = master.name;
      _usernameController.text = master.username;
      _creditController.text = master.credits.toString();
      _noteController.text = master.note;
      _profitLossController.text = master.pnlSharing.toString();
      _brkSharingController.text = master.brokerageSharing.toString();
      _addMaster = master.addMaster;
      _changePasswordOnFirstLogin = master.changePassOnFirstLogin;
      _selectedServerId = master.serverId;

      for (var exchange in master.exchangesAllowed) {
        String key = exchange == 'INDICES' ? 'GLOBAL' : exchange;
        if (_exchangeAllow.containsKey(key)) {
          _exchangeAllow[key] = true;
        }
      }
      for (var exchange in master.tradeLimit) {
        String key = exchange == 'INDICES' ? 'GLOBAL' : exchange;
        if (_highLowBetweenTradeLimit.containsKey(key)) {
          _highLowBetweenTradeLimit[key] = true;
        }
      }
    }
  }

  Future<void> _fetchServers() async {
    setState(() => _isLoadingServers = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final response = await adminService.getAllServers();
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _servers =
                List<Map<String, dynamic>>.from(data['data']['servers'] ?? []);
          });
          log('✅ Loaded ${_servers.length} servers');
        }
      }
    } catch (e) {
      log('❌ Error fetching servers: $e');
    } finally {
      setState(() => _isLoadingServers = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('Please enter name', isError: true);
      return;
    }
    if (_usernameController.text.trim().isEmpty) {
      _showSnack('Please enter username', isError: true);
      return;
    }
    if (_passwordController.text.isNotEmpty ||
        _confirmPasswordController.text.isNotEmpty) {
      if (_passwordController.text != _confirmPasswordController.text) {
        _showSnack('Passwords do not match', isError: true);
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      final selectedExchanges = _exchangeAllow.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();
      final selectedTradeLimit = _highLowBetweenTradeLimit.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      if (widget.master != null) {
        final response = await adminService.updateMaster(
          masterId: widget.master!.id,
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          credits: double.tryParse(_creditController.text.trim()),
          note: _noteController.text.trim().isEmpty
              ? ''
              : _noteController.text.trim(),
          pnlSharing: double.tryParse(_profitLossController.text.trim()),
          brokerageSharing: double.tryParse(_brkSharingController.text.trim()),
          exchangesAllowed: selectedExchanges,
          tradeLimit: selectedTradeLimit,
          addMaster: _addMaster,
          changePassOnFirstLogin: _changePasswordOnFirstLogin,
        );
        if (response.statusCode == 200) {
          if (mounted) {
            _showSnack('Master updated successfully');
            Navigator.pop(context, true);
          }
        } else {
          _showSnack('Failed to update master', isError: true);
        }
      } else {
        if (_passwordController.text.trim().isEmpty) {
          _showSnack('Password is required for new master', isError: true);
          setState(() => _isSubmitting = false);
          return;
        }

        final profileProvider =
            Provider.of<UserProfileProvider>(context, listen: false);
        String? serverId;

        if (profileProvider.isAdmin) {
          serverId = _selectedServerId;
          if (serverId == null || serverId.isEmpty) {
            _showSnack('Please select a server', isError: true);
            setState(() => _isSubmitting = false);
            return;
          }
        } else {
          serverId = profileProvider.master?.serverId;
          if (serverId == null || serverId.isEmpty) {
            _showSnack('Server ID not found. Please logout and login again.',
                isError: true);
            setState(() => _isSubmitting = false);
            return;
          }

          // Validate PnL and Brokerage sharing for master creating child master
          final pnlSharing =
              double.tryParse(_profitLossController.text.trim()) ?? 0;
          final brkSharing =
              double.tryParse(_brkSharingController.text.trim()) ?? 0;
          final parentPnl = profileProvider.master?.pnlSharing ?? 100;
          final parentBrk = profileProvider.master?.brokerageSharing ?? 100;

          if (pnlSharing > parentPnl) {
            _showSnack(
                'P&L sharing cannot exceed your available share of ${parentPnl.toStringAsFixed(1)}%',
                isError: true);
            setState(() => _isSubmitting = false);
            return;
          }

          if (brkSharing > parentBrk) {
            _showSnack(
                'Brokerage sharing cannot exceed your available share of ${parentBrk.toStringAsFixed(1)}%',
                isError: true);
            setState(() => _isSubmitting = false);
            return;
          }
        }

        // Initial Trade Wallet funding (optional; only for allowed categories).
        final walletMap = _buildWalletMap(allowedCategories(selectedExchanges));
        final response = await adminService.createMaster(
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          credits: double.tryParse(_creditController.text.trim()) ?? 0,
          note: _noteController.text.trim().isEmpty
              ? ''
              : _noteController.text.trim(),
          pnlSharing: double.tryParse(_profitLossController.text.trim()) ?? 0,
          brokerageSharing:
              double.tryParse(_brkSharingController.text.trim()) ?? 0,
          exchangesAllowed: selectedExchanges,
          tradeLimit: selectedTradeLimit,
          addMaster: _addMaster,
          changePassOnFirstLogin: _changePasswordOnFirstLogin,
          serverId: serverId,
          wallet: walletMap.isEmpty ? null : walletMap,
        );

        if (response.statusCode == 201) {
          if (mounted) {
            _isSuccess = true;
            await profileProvider.fetchProfile();
            _showSnack('Master created successfully');
            Navigator.pop(context, true);
          }
        } else {
          final body = jsonDecode(response.body);
          final errorMsg = body['message'] ?? 'Failed to create master';
          _showSnack(errorMsg, isError: true);
        }
      }
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
                    widget.master != null ? 'Edit Master' : 'Create Master',
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
                    // Personal Details
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
                              controller: _usernameController,
                              readOnly: widget.master == null),
                          // Server dropdown for admin
                          Consumer<UserProfileProvider>(
                            builder: (context, profile, _) {
                              if (!profile.isAdmin)
                                return const SizedBox.shrink();
                              return Column(
                                children: [
                                  _divider(),
                                  _buildDropdownField(
                                    label: 'Server',
                                    hint: _isLoadingServers
                                        ? 'Loading...'
                                        : 'Select Server',
                                    value: _selectedServerId,
                                    onChanged: (v) =>
                                        setState(() => _selectedServerId = v),
                                    items: _servers
                                        .map((s) => s['id'] as String)
                                        .toList(),
                                    itemLabels: _servers
                                        .map((s) => s['name'] as String)
                                        .toList(),
                                  ),
                                ],
                              );
                            },
                          ),
                          _divider(),
                          _buildTextField(
                            label: 'Password',
                            controller: _passwordController,
                            obscureText: true,
                            hint: widget.master != null
                                ? 'Leave empty to keep current'
                                : 'Enter password',
                          ),
                          _divider(),
                          _buildTextField(
                            label: 'Confirm Password',
                            controller: _confirmPasswordController,
                            obscureText: true,
                            hint: widget.master != null
                                ? 'Leave empty to keep current'
                                : 'Confirm password',
                          ),
                          _divider(),
                          _buildTextField(
                              label: 'Credit',
                              controller: _creditController,
                              keyboardType: TextInputType.number),
                          _divider(),
                          _buildTextField(
                              label: 'Note / Remark',
                              controller: _noteController,
                              hint: 'Optional'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // P&L Sharing
                    _sectionLabel('PARTNERSHIP SHARE'),
                    const SizedBox(height: 12),
                    _buildSharingCard(
                      title: 'Profit & Loss Sharing',
                      controller: _profitLossController,
                      getParentValue: (p) => p.master?.pnlSharing ?? 100,
                    ),
                    const SizedBox(height: 12),
                    _buildSharingCard(
                      title: 'BRK Sharing',
                      controller: _brkSharingController,
                      getParentValue: (p) => p.master?.brokerageSharing ?? 100,
                    ),

                    const SizedBox(height: 24),

                    // Exchange Allow
                    _buildCheckboxSection(
                      label: 'EXCHANGE ALLOW',
                      values: _exchangeAllow,
                      onToggleAll: () {
                        setState(() {
                          final all = _exchangeAllow.values.every((v) => v);
                          _exchangeAllow.updateAll((k, v) => !all);
                        });
                      },
                    ),

                    const SizedBox(height: 24),

                    // Trade Limit
                    _buildCheckboxSection(
                      label: 'HIGH LOW BETWEEN TRADE LIMIT',
                      values: _highLowBetweenTradeLimit,
                      onToggleAll: () {
                        setState(() {
                          final all =
                              _highLowBetweenTradeLimit.values.every((v) => v);
                          _highLowBetweenTradeLimit.updateAll((k, v) => !all);
                        });
                      },
                    ),

                    const SizedBox(height: 24),

                    // Trade Wallet
                    _buildWalletSection(),

                    const SizedBox(height: 24),

                    // Toggles
                    _card(
                      child: Column(
                        children: [
                          _buildToggleRow('Add Master', _addMaster,
                              (v) => setState(() => _addMaster = v)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Submit
                    GestureDetector(
                      onTap: _isSubmitting ? null : _handleSubmit,
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
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  widget.master != null
                                      ? 'UPDATE MASTER'
                                      : 'CREATE MASTER',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: kFontSizeButtonText,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold,
                                    letterSpacing: 0.3,
                                  ),
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
    String? hint,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: kFontSizeBodySmall,
                fontFamily: 'Inter',
                fontWeight: kFontWeightMedium,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              readOnly: readOnly,
              style: readOnly
                  ? const TextStyle(color: Colors.grey)
                  : const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeBody,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium,
                    ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint ?? label,
                hintStyle: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: kFontSizeBody,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String hint,
    required String? value,
    required Function(String?) onChanged,
    required List<String> items,
    List<String>? itemLabels,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: kFontSizeBodySmall,
                fontFamily: 'Inter',
                fontWeight: kFontWeightMedium,
              ),
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                hint: Text(
                  hint,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: kFontSizeBody,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightRegular,
                  ),
                ),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down,
                    size: 18, color: Color(0xFF94A3B8)),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: kFontSizeBody,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightMedium,
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(16),
                onChanged: onChanged,
                items: items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final lbl = itemLabels != null && idx < itemLabels.length
                      ? itemLabels[idx]
                      : item;
                  return DropdownMenuItem<String>(
                      value: item, child: Text(lbl));
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharingCard({
    required String title,
    required TextEditingController controller,
    required double Function(UserProfileProvider) getParentValue,
  }) {
    return Consumer<UserProfileProvider>(
      builder: (context, profile, _) {
        final isMaster = profile.isMaster;
        final parentVal = isMaster ? getParentValue(profile) : 100.0;
        final entered = double.tryParse(controller.text) ?? 0;
        final remaining = parentVal - entered;

        return _card(
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
              const SizedBox(height: 12),
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: kFontSizeBody,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightMedium,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter value',
                    hintStyle: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: kFontSizeBody,
                        fontFamily: 'Inter'),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F45C7).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isMaster
                            ? 'Our: ${parentVal.toStringAsFixed(1)}'
                            : 'Our: 100',
                        style: const TextStyle(
                          color: Color(0xFF3F45C7),
                          fontSize: kFontSizeSubtitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (remaining < 0
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF10B981))
                            .withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Remaining: ${remaining.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: remaining < 0
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                          fontSize: kFontSizeSubtitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheckboxSection({
    required String label,
    required Map<String, bool> values,
    required VoidCallback onToggleAll,
  }) {
    final keys = values.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel(label),
            GestureDetector(
              onTap: onToggleAll,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  values.values.every((v) => v) ? 'Deselect All' : 'Select All',
                  style: const TextStyle(
                    color: Color(0xFF3F45C7),
                    fontSize: kFontSizeNavLabel,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightSemiBold,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _card(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: keys.map((key) {
              final selected = values[key]!;
              return GestureDetector(
                onTap: () => setState(() => values[key] = !selected),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF3F45C7)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF3F45C7)
                          : const Color(0xFFF1F5F9),
                    ),
                  ),
                  child: Text(
                    key,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF64748B),
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
      ],
    );
  }

  // ── Trade Wallet section ──

  Widget _buildWalletSection() {
    final cats = allowedCategories(_selectedExchangeNames);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('TRADE WALLET'),
        const SizedBox(height: 12),
        _card(
          child: cats.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Select exchanges to fund wallet',
                    style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: kFontSizeBodySmall,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium),
                  ),
                )
              : Column(
                  children: [
                    for (int i = 0; i < cats.length; i++) ...[
                      _buildWalletRow(cats[i]),
                      if (i != cats.length - 1) _divider(),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildWalletRow(String category) {
    final controller = _walletControllerFor(category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  category,
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeBody,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
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
          Builder(builder: (_) {
            final parsed = double.tryParse(controller.text.trim());
            final words = numberToIndianWords(parsed);
            if (words.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(left: 110, top: 2),
              child: Text(
                '₹ $words',
                style: const TextStyle(
                  color: Color(0xFF3F45C7),
                  fontSize: 11,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildToggleRow(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
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
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
