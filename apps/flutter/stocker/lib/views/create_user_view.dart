import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer';
import '../providers/user_profile_provider.dart';
import '../services/admin_service.dart';
import '../models/user.dart';

class CreateUserView extends StatefulWidget {
  final User? user; // Optional user parameter for edit mode

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
  Map<String, List<String>> _exchangeLotNames =
      {}; // Store lot names for each exchange

  List<String> _allowedExchanges = [];
  List<String> _allowedTradeLimit = [];

  @override
  void initState() {
    super.initState();
    _loadMasterPermissions();

    // Pre-fill data if editing existing user
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
        // Get allowed exchanges from master
        _allowedExchanges = profileProvider.master!.exchangesAllowed;
        _allowedTradeLimit = profileProvider.master!.tradeLimit;

        // Initialize exchange settings only for allowed exchanges
        _exchangeSettings = {};
        for (var exchange in _allowedExchanges) {
          _exchangeSettings[exchange] = {
            'enabled': false,
            'turnover': false,
            'lot': false,
            'group': null
          };
        }

        // If editing, pre-fill exchange settings from user data
        if (widget.user != null) {
          for (var userExchange in widget.user!.exchangesAllowed) {
            if (_exchangeSettings.containsKey(userExchange.exchangeName)) {
              _exchangeSettings[userExchange.exchangeName] = {
                'enabled': true,
                'turnover': userExchange.turnover,
                'lot': userExchange.lot,
                'group': userExchange.groupName.isNotEmpty
                    ? userExchange.groupName
                    : null
              };
            }
          }
        }

        // Initialize trade limit only for allowed exchanges
        _tradeLimit = {};
        for (var exchange in _allowedTradeLimit) {
          _tradeLimit[exchange] =
              widget.user?.tradeLimit.contains(exchange) ?? false;
        }
      });

      // Fetch lot names for each exchange
      for (var exchange in _allowedExchanges) {
        _fetchLotNamesForExchange(exchange, adminService);
      }
    }
  }

  Future<void> _fetchLotNamesForExchange(
      String exchange, AdminService adminService) async {
    try {
      log('🔍 Fetching lot names for exchange: $exchange');
      final response = await adminService.getLotNamesByExchange(exchange);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final lotNames = List<String>.from(data['data']);
          setState(() {
            _exchangeLotNames[exchange] = lotNames;
          });
          log('✅ Loaded ${lotNames.length} lot names for $exchange');
        }
      } else {
        log('❌ Failed to fetch lot names for $exchange: ${response.statusCode}');
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

  Future<void> _createUser() async {
    // Validation
    if (_nameController.text.trim().isEmpty) {
      _showError('Please enter name');
      return;
    }

    if (_usernameController.text.trim().isEmpty) {
      _showError('Please enter username');
      return;
    }

    // Password validation - required for create, optional for update
    if (widget.user == null) {
      // Creating new user - password is required
      if (_passwordController.text.isEmpty) {
        _showError('Please enter password');
        return;
      }

      if (_passwordController.text != _confirmPasswordController.text) {
        _showError('Passwords do not match');
        return;
      }
    } else {
      // Updating existing user - password is optional
      if (_passwordController.text.isNotEmpty &&
          _passwordController.text != _confirmPasswordController.text) {
        _showError('Passwords do not match');
        return;
      }
    }

    if (_creditController.text.trim().isEmpty) {
      _showError('Please enter credit amount');
      return;
    }

    final credit = double.tryParse(_creditController.text.trim());
    if (credit == null || credit < 0) {
      _showError('Please enter a valid credit amount');
      return;
    }

    // Get profile provider to access master data
    final profileProvider =
        Provider.of<UserProfileProvider>(context, listen: false);
    if (profileProvider.master == null) {
      _showError('Master profile not found');
      return;
    }

    // Prepare exchanges_allowed array
    List<Map<String, dynamic>> exchangesAllowed = [];
    _exchangeSettings.forEach((exchange, settings) {
      if (settings['enabled'] == true) {
        exchangesAllowed.add({
          'exchange_name': exchange.toUpperCase(), // Ensure uppercase
          'turnover': settings['turnover'] ?? false,
          'lot': settings['lot'] ?? false,
          'group_name': settings['group'] ?? '',
        });
      }
    });

    if (exchangesAllowed.isEmpty) {
      _showError('Please select at least one exchange');
      return;
    }

    // Prepare trade_limit array
    List<String> tradeLimitList = [];
    _tradeLimit.forEach((exchange, enabled) {
      if (enabled) {
        tradeLimitList.add(exchange.toUpperCase()); // Ensure uppercase
      }
    });

    setState(() {
      _isSubmitting = true;
    });

    try {
      final adminService = Provider.of<AdminService>(context, listen: false);

      http.Response response;

      if (widget.user != null) {
        // Update existing user
        log('📤 Updating user...');
        response = await adminService.updateUser(
          userId: widget.user!.id,
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          credits: credit,
          note: _noteController.text.trim(),
          pnlSharing: profileProvider.master!.pnlSharing,
          brokerageSharing: profileProvider.master!.brokerageSharing,
          exchangesAllowed: exchangesAllowed,
          tradeLimit: tradeLimitList,
          marginSquareOff: _marginSquareOff,
          changePassOnFirstLogin: _changePasswordOnFirstLogin,
        );
      } else {
        // Create new user
        log('📤 Creating user...');
        response = await adminService.createUser(
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          credits: credit,
          note: _noteController.text.trim(),
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
        log(widget.user != null
            ? '✅ User updated successfully'
            : '✅ User created successfully');

        // Refresh master profile to update credits
        await profileProvider.refreshProfile();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.user != null
                ? 'User updated successfully'
                : 'User created successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        log('❌ Failed to ${widget.user != null ? 'update' : 'create'} user: ${data['message']}');
        _showError(data['message'] ??
            'Failed to ${widget.user != null ? 'update' : 'create'} user');
      }
    } catch (e) {
      log('❌ Error ${widget.user != null ? 'updating' : 'creating'} user: $e');
      if (mounted) {
        _showError(
            'Error ${widget.user != null ? 'updating' : 'creating'} user: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
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
                    child: const Icon(Icons.arrow_back, color: Colors.black),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.user != null ? 'Edit User' : 'Create User',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Personal Details Section
                    const Text(
                      'PERSONAL DETAILS',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildTextField(
                              label: 'Name', controller: _nameController),
                          const SizedBox(height: 16),
                          _buildTextField(
                              label: 'Username',
                              controller: _usernameController),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Password',
                            controller: _passwordController,
                            obscureText: true,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Confirm Password',
                            controller: _confirmPasswordController,
                            obscureText: true,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Credit',
                            controller: _creditController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                              label: 'Note/Remark',
                              controller: _noteController),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Exchange Allow Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'EXCHANGE ALLOW',
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              bool allEnabled = _exchangeSettings.values
                                  .every((v) => v['enabled']);
                              _exchangeSettings.forEach((key, value) {
                                value['enabled'] = !allEnabled;
                              });
                            });
                          },
                          child:
                              const Icon(Icons.check_circle_outline, size: 24),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    _exchangeSettings.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'No exchanges available',
                                style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.all(12),
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Column(
                              children: [
                                // Header Row
                                Row(
                                  children: [
                                    const Expanded(
                                      flex: 2,
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Text(
                                          'Exchange',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: Text(
                                          'Turnover',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.visible,
                                        ),
                                      ),
                                    ),
                                    const Expanded(
                                      flex: 1,
                                      child: Center(
                                        child: Text(
                                          'Lot',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 148,
                                      child: Center(
                                        child: Text(
                                          'Assign Group',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Exchange Rows
                                ..._exchangeSettings.entries.map((entry) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildExchangeRow(
                                        entry.key, entry.value),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),

                    const SizedBox(height: 24),

                    // High Low Between Trade Limit Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'HIGH LOW BETWEEN TRADE LIMIT',
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              bool allSelected =
                                  _tradeLimit.values.every((v) => v);
                              _tradeLimit
                                  .updateAll((key, value) => !allSelected);
                            });
                          },
                          child:
                              const Icon(Icons.check_circle_outline, size: 24),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),

                    _tradeLimit.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'No trade limits available',
                                style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.all(16),
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Column(
                              children: _buildTradeLimitRows(),
                            ),
                          ),

                    const SizedBox(height: 24),

                    // Toggle Switches
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildToggleRow(
                            'Margin Square Off',
                            _marginSquareOff,
                            (value) => setState(() => _marginSquareOff = value),
                          ),
                          const SizedBox(height: 16),
                          if (widget.user == null) ...[
                            _buildToggleRow(
                              'Change password on first login',
                              _changePasswordOnFirstLogin,
                              (value) => setState(
                                  () => _changePasswordOnFirstLogin = value),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Create Button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _isSubmitting ? null : _createUser,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 18),
                          decoration: ShapeDecoration(
                            color: _isSubmitting
                                ? const Color(0xFF8E8E93)
                                : const Color(0xFF22547C),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSubmitting
                              ? const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.user != null
                                      ? 'UPDATE USER'
                                      : 'CREATE USER',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Placeholder',
              hintStyle: TextStyle(
                color: Color(0xFF8E8E93),
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
    );
  }

  Widget _buildExchangeRow(String exchange, Map<String, dynamic> settings) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    settings['enabled'] = !settings['enabled'];
                  });
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: settings['enabled']
                        ? const Color(0xFF22547C)
                        : Colors.transparent,
                    border: Border.all(
                      color: settings['enabled']
                          ? const Color(0xFF22547C)
                          : const Color(0xFFC7C7CC),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: settings['enabled']
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exchange,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: GestureDetector(
            onTap: () {
              setState(() {
                settings['turnover'] = !settings['turnover'];
              });
            },
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: settings['turnover']
                      ? const Color(0xFF22547C)
                      : Colors.transparent,
                  border: Border.all(
                    color: settings['turnover']
                        ? const Color(0xFF22547C)
                        : const Color(0xFFC7C7CC),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: settings['turnover']
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: GestureDetector(
            onTap: () {
              setState(() {
                settings['lot'] = !settings['lot'];
              });
            },
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: settings['lot']
                      ? const Color(0xFF22547C)
                      : Colors.transparent,
                  border: Border.all(
                    color: settings['lot']
                        ? const Color(0xFF22547C)
                        : const Color(0xFFC7C7CC),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: settings['lot']
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 148,
          height: 48,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: settings['group'],
                hint: Text(
                  _exchangeLotNames[exchange]?.isEmpty ?? true
                      ? 'No groups'
                      : 'Select Item',
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                isExpanded: true,
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onChanged: (_exchangeLotNames[exchange]?.isEmpty ?? true)
                    ? null
                    : (value) {
                        setState(() {
                          settings['group'] = value;
                        });
                      },
                items:
                    (_exchangeLotNames[exchange] ?? []).map((String lotName) {
                  return DropdownMenuItem<String>(
                    value: lotName,
                    child: Text(
                      lotName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'Inter',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckboxItem(
      String label, bool value, Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF22547C) : Colors.transparent,
                border: Border.all(
                  color:
                      value ? const Color(0xFF22547C) : const Color(0xFFC7C7CC),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: value
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 40,
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: ShapeDecoration(
              color: value ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.50),
              ),
            ),
            child: Align(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 23,
                height: 23,
                decoration: const ShapeDecoration(
                  color: Colors.white,
                  shape: OvalBorder(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTradeLimitRows() {
    List<Widget> rows = [];
    List<String> exchanges = _tradeLimit.keys.toList();

    // Build rows with 2 items each
    for (int i = 0; i < exchanges.length; i += 2) {
      List<Widget> rowItems = [];

      // First item
      rowItems.add(
        Expanded(
          child: _buildCheckboxItem(
            exchanges[i],
            _tradeLimit[exchanges[i]]!,
            (value) {
              setState(() {
                _tradeLimit[exchanges[i]] = value;
              });
            },
          ),
        ),
      );

      // Second item if exists
      if (i + 1 < exchanges.length) {
        rowItems.add(const SizedBox(width: 12));
        rowItems.add(
          Expanded(
            child: _buildCheckboxItem(
              exchanges[i + 1],
              _tradeLimit[exchanges[i + 1]]!,
              (value) {
                setState(() {
                  _tradeLimit[exchanges[i + 1]] = value;
                });
              },
            ),
          ),
        );
      } else {
        // Add empty space if odd number of items
        rowItems.add(const SizedBox(width: 12));
        rowItems.add(const Expanded(child: SizedBox()));
      }

      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < exchanges.length ? 12 : 0),
          child: Row(children: rowItems),
        ),
      );
    }

    return rows;
  }
}
