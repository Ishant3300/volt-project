import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../utils/number_to_words.dart';
import '../models/master.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
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
  final TextEditingController _investorPasswordController =
      TextEditingController();
  final TextEditingController _confirmInvestorPasswordController =
      TextEditingController();
  final TextEditingController _creditController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _profitLossController = TextEditingController();
  final TextEditingController _brkSharingController = TextEditingController();

  bool _addMaster = false;
  bool _changePasswordOnFirstLogin = true;
  bool _isSubmitting = false;

  // Product-specific brokerage: NFO-FUT/NFO-OPT can split Index vs Stock,
  // MCX-FUT/MCX-OPT can set every script individually — both opt-in via a
  // "Customize" toggle per exchange row, instead of the one flat value.
  static const _categorySegments = {'NFO-FUT', 'NFO-OPT'};
  static const _perScriptSegments = {'MCX-FUT', 'MCX-OPT'};
  final Map<String, bool> _brokerageCustomized = {};
  final Map<String, TextEditingController> _indexBrkControllers = {};
  final Map<String, TextEditingController> _stockBrkControllers = {};
  final Map<String, List<Map<String, dynamic>>> _segmentScripts = {};
  final Map<String, Map<String, TextEditingController>> _scriptBrkControllers =
      {};
  final Map<String, bool> _loadingScripts = {};

  // Multi-select "apply value to several scripts at once" for per-script
  // segments (MCX-FUT/MCX-OPT) — check ALUMINI/COPPER/LEAD/ZINC, type one
  // value, tap apply, and all four fill in one go instead of typing into
  // each field individually. Purely a faster way to populate the SAME
  // per-script controllers _applyBrokerageSettings already reads on
  // submit — no new submission path, so a script left unchecked still
  // falls back to the flat value exactly as already fixed above.
  final Map<String, Set<String>> _selectedScriptsForBulk = {};
  final Map<String, TextEditingController> _bulkScriptValueControllers = {};
  final Map<String, String?> _bulkApplyError = {};

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
    'GLOBAL': false,
    'COMEX-FUT': false,
  };

  Map<String, bool> _highLowBetweenTradeLimit = {
    'NFO-FUT': false,
    'NFO-OPT': false,
    'MCX-FUT': false,
    'MCX-OPT': false,
    'GLOBAL': false,
    'COMEX-FUT': false,
  };

  // Admin-only: which GroupedQuantity group(s) this master may use for their
  // own script quantity setting AND hand out to their clients. Backend
  // enforces this as a hard ceiling regardless of what this form sends
  // (masterController.js/masterChildController.js's isGroupAllotted check)
  // — this UI is just what the create/edit form offers to check.
  final Map<String, Set<String>> _allottedGroups = {
    'NFO-FUT': <String>{},
    'NFO-OPT': <String>{},
    'MCX-FUT': <String>{},
    'MCX-OPT': <String>{},
    'GLOBAL': <String>{},
    'COMEX-FUT': <String>{},
  };
  final Map<String, List<String>> _availableGroupsByExchange = {};
  bool _isLoadingAvailableGroups = false;

  // Trade Wallet inputs per allowed category (NSE/MCX/GLOBAL)
  final Map<String, TextEditingController> _walletControllers = {};

  // Brokerage settings per exchange (inline during creation)
  Map<String, Map<String, dynamic>> _brokerageSettings = {};

  // The logged-in master's OWN rate per exchange — the real floor a new
  // sub-broker's flat brokerage can't be set below (mirrors the backend's
  // own enforceFloor/validateBrokerageFloor rejection in
  // brokerageCopyService.js). Only meaningful when a master (not an admin
  // creating a top-level master directly) is doing the creating — same
  // "no parent to violate against" case the backend itself skips.
  final Map<String, double> _brokerageFloor = {};

  @override
  void dispose() {
    if (!_isSuccess) _releaseUsername();
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _investorPasswordController.dispose();
    _confirmInvestorPasswordController.dispose();
    _creditController.dispose();
    _noteController.dispose();
    _profitLossController.dispose();
    _brkSharingController.dispose();
    for (final controller in _walletControllers.values) {
      controller.dispose();
    }
    for (final controller in _bulkScriptValueControllers.values) {
      controller.dispose();
    }
    for (final entry in _brokerageSettings.values) {
      (entry['controller'] as TextEditingController?)?.dispose();
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

    // Allotted Groups is an admin-only control (see field comment) — only
    // fetch the group catalog when this form is actually admin-driven.
    final isAdminCaller =
        Provider.of<UserProfileProvider>(context, listen: false).isAdmin;
    if (isAdminCaller) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAvailableGroups());
    }

    _profitLossController.addListener(() => setState(() {}));
    _brkSharingController.addListener(() => setState(() {}));

    // Initialize brokerage settings for all exchanges
    _brokerageSettings = {};
    for (var exchange in _exchangeAllow.keys) {
      final isLotSegment = exchange == 'NFO-OPT' ||
          exchange == 'MCX-FUT' ||
          exchange == 'MCX-OPT' ||
          exchange == 'COMEX-FUT';
      _brokerageSettings[exchange] = {
        'type': isLotSegment ? 'LOT WISE' : 'TURNOVER WISE',
        'value': '',
        'controller': TextEditingController(),
      };
    }

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
      for (var g in master.allottedScriptQuantityGroups) {
        final ex = g['exchange_name']?.toString();
        final key = ex == 'INDICES' ? 'GLOBAL' : ex;
        if (key != null && _allottedGroups.containsKey(key)) {
          final names = (g['group_names'] as List?)
                  ?.map((e) => e.toString())
                  .toSet() ??
              <String>{};
          _allottedGroups[key] = names;
        }
      }
    } else {
      // New sub-broker, created by a master (not an admin creating a
      // top-level master, which has no parent to floor against) —
      // pre-fill every rate field from the creating master's own rate.
      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      if (!profileProvider.isAdmin) {
        _fetchOwnBrokerageFloor();
      }
    }
  }

  /// Pre-fills the "Base rate" fields (currently blank on this screen) from
  /// the logged-in master's own rate, and records the same values as the
  /// floor _createMaster checks against before submit. Mirrors
  /// _fetchCurrentBrokerage in create_user_view.dart.
  Future<void> _fetchOwnBrokerageFloor() async {
    // Read BEFORE the first await below — same reasoning as
    // create_user_view.dart's _fetchCurrentBrokerage.
    final ownMasterId =
        Provider.of<UserProfileProvider>(context, listen: false).master?.id;
    if (ownMasterId == null) return;
    try {
      final token = await SecureStorageService().getToken();
      final apiService = ApiService(backendUrl);

      for (final exchange in _brokerageSettings.keys.toList()) {
        final apiExchange = exchange == 'GLOBAL' ? 'INDICES' : exchange;
        final brkSettings = _brokerageSettings[exchange];
        if (brkSettings == null) continue;
        final type = brkSettings['type'] as String;
        final res = await apiService.get(
          '/admin/brokerage-settings/exchange/$apiExchange?type=${Uri.encodeComponent(type)}&limit=1&user_id=$ownMasterId',
          token: token,
        );
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body['success'] == true) {
            final items = body['data']['items'] as List? ?? [];
            if (items.isNotEmpty) {
              final firstVal =
                  (items[0]['brk_value'] as num?)?.toDouble() ?? 0;
              if (mounted) {
                setState(() {
                  brkSettings['value'] = firstVal.toString();
                  (brkSettings['controller'] as TextEditingController).text =
                      firstVal % 1 == 0
                          ? firstVal.toInt().toString()
                          : firstVal.toString();
                  _brokerageFloor[exchange] = firstVal;
                });
              }
            }
          }
        }
      }
    } catch (e) {
      log('⚠️ Error fetching own brokerage floor: \$e');
    }
  }

  Future<void> _fetchAvailableGroups() async {
    setState(() => _isLoadingAvailableGroups = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      for (final exchange in _exchangeAllow.keys) {
        // Backend stores INDICES, but UI uses GLOBAL — same mapping already
        // used by create_user_view.dart's own group fetch.
        final apiExchange = exchange == 'GLOBAL' ? 'INDICES' : exchange;
        try {
          final response = await adminService.getLotNamesByExchange(apiExchange);
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true && data['data'] != null) {
              _availableGroupsByExchange[exchange] =
                  List<String>.from(data['data']);
            }
          }
        } catch (e) {
          log('❌ Error fetching groups for $exchange: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _isLoadingAvailableGroups = false);
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

    // Validate investor password (optional — only if filled)
    if (_investorPasswordController.text.isNotEmpty) {
      if (_investorPasswordController.text !=
          _confirmInvestorPasswordController.text) {
        _showSnack('Investor passwords do not match', isError: true);
        return;
      }
      if (_investorPasswordController.text == _passwordController.text) {
        _showSnack('Investor password must be different from main password',
            isError: true);
        return;
      }
    }

    // Floor check — mirrors the backend's own enforceFloor/
    // validateBrokerageFloor rejection (brokerageCopyService.js), surfaced
    // here before the request instead of after a failed submit. Only
    // applies to a NEW sub-broker created by a master (an admin creating a
    // top-level master directly has no parent to violate against, same as
    // the backend skips it there) and only covers the flat per-exchange
    // rate, not the per-script/per-category customize sub-fields.
    if (widget.master == null && _brokerageFloor.isNotEmpty) {
      for (final exchange in _exchangeAllow.keys) {
        if (_exchangeAllow[exchange] != true) continue;
        final brkSettings = _brokerageSettings[exchange];
        final floor = _brokerageFloor[exchange];
        if (brkSettings == null || floor == null) continue;
        final entered = double.tryParse(
            (brkSettings['controller'] as TextEditingController).text.trim());
        if (entered != null && entered < floor) {
          _showSnack(
              '$exchange brokerage ($entered) cannot be less than your own rate ($floor).',
              isError: true);
          return;
        }
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
      // Only exchanges actually allowed AND with at least one group checked
      // get sent — an unchecked exchange stays unrestricted server-side.
      final allottedGroupsPayload = _allottedGroups.entries
          .where((e) =>
              _exchangeAllow[e.key] == true && e.value.isNotEmpty)
          .map((e) => {
                'exchange_name': e.key == 'GLOBAL' ? 'INDICES' : e.key,
                'group_names': e.value.toList(),
              })
          .toList();

      if (widget.master != null) {
        final response = await adminService.updateMaster(
          masterId: widget.master!.id,
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          investorPassword: _investorPasswordController.text.isNotEmpty
              ? _investorPasswordController.text
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
          allottedScriptQuantityGroups:
              allottedGroupsPayload.isEmpty ? null : allottedGroupsPayload,
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

          // Own-balance guard: a master can't hand out more credit/wallet
          // than they themselves currently have — same checks the backend
          // itself enforces (parentMaster.equity < credits /
          // walletService.block), just surfaced here before the request.
          final ownMaster = profileProvider.master;
          if (ownMaster != null) {
            final creditEntered =
                double.tryParse(_creditController.text.trim()) ?? 0;
            if (creditEntered > ownMaster.equity) {
              _showSnack(
                  'Opening credit exceeds your own available balance (${ownMaster.equity.toStringAsFixed(2)}).',
                  isError: true);
              setState(() => _isSubmitting = false);
              return;
            }
            for (final category
                in allowedCategories(selectedExchanges)) {
              final entered = double.tryParse(
                      _walletControllerFor(category).text.trim()) ??
                  0;
              final available = ownMaster.wallet[category] ?? 0;
              if (entered > available) {
                _showSnack(
                    '$category wallet amount exceeds your own available balance (${available.toStringAsFixed(2)}).',
                    isError: true);
                setState(() => _isSubmitting = false);
                return;
              }
            }
          }
        }

        // Initial Trade Wallet funding (optional; only for allowed categories).
        final walletMap = _buildWalletMap(allowedCategories(selectedExchanges));
        final response = await adminService.createMaster(
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          investorPassword: _investorPasswordController.text.isNotEmpty
              ? _investorPasswordController.text
              : null,
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
          allottedScriptQuantityGroups:
              allottedGroupsPayload.isEmpty ? null : allottedGroupsPayload,
        );

        if (response.statusCode == 201) {
          if (mounted) {
            _isSuccess = true;
            // Apply brokerage settings for the new master
            final body = jsonDecode(response.body);
            final createdId =
                body['data']?['child_master']?['id']?.toString() ??
                    body['data']?['id']?.toString() ??
                    body['data']?['_id']?.toString();
            await _applyBrokerageSettings(createdId);
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

  /// Toggle the per-category (NFO) or per-script (MCX) brokerage editor for
  /// one exchange row, fetching that segment's scripts (with category) the
  /// first time it's opened.
  Future<void> _toggleCustomizeBrokerage(String exchange) async {
    final willOpen = !(_brokerageCustomized[exchange] ?? false);
    setState(() => _brokerageCustomized[exchange] = willOpen);
    if (!willOpen || _segmentScripts.containsKey(exchange)) return;

    setState(() => _loadingScripts[exchange] = true);
    try {
      final adminService =
          AdminService(Provider.of<ApiService>(context, listen: false));
      final res = await adminService.getUniqueRawNamesBySegment(exchange);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          final scripts = List<Map<String, dynamic>>.from(body['data'] ?? []);
          _segmentScripts[exchange] = scripts;
          if (_perScriptSegments.contains(exchange)) {
            _scriptBrkControllers[exchange] = {
              for (final s in scripts)
                (s['raw_name'] as String): TextEditingController(),
            };
          }
        }
      }
    } catch (e) {
      log('⚠️ Error fetching scripts for $exchange: $e');
    } finally {
      if (mounted) setState(() => _loadingScripts[exchange] = false);
    }
  }

  TextEditingController _categoryController(String exchange, String category) {
    final map =
        category == 'INDEX' ? _indexBrkControllers : _stockBrkControllers;
    return map.putIfAbsent(exchange, () => TextEditingController());
  }

  TextEditingController _bulkScriptValueController(String exchange) =>
      _bulkScriptValueControllers.putIfAbsent(exchange, () => TextEditingController());

  /// Fills every checked script's own controller with the typed value, then
  /// clears the selection so the next batch starts fresh.
  void _applyBulkScriptValue(String exchange) {
    final controller = _bulkScriptValueController(exchange);
    final raw = controller.text.trim();
    final value = double.tryParse(raw);
    final selected = _selectedScriptsForBulk[exchange] ?? {};

    setState(() {
      if (raw.isEmpty || value == null || value <= 0) {
        _bulkApplyError[exchange] = 'Enter a valid value first';
        return;
      }
      if (selected.isEmpty) {
        _bulkApplyError[exchange] = 'Select at least one script';
        return;
      }
      final scriptControllers = _scriptBrkControllers[exchange] ?? const {};
      final display = value % 1 == 0 ? value.toInt().toString() : value.toString();
      for (final script in selected) {
        scriptControllers[script]?.text = display;
      }
      _selectedScriptsForBulk[exchange] = {};
      _bulkApplyError[exchange] = null;
      controller.clear();
    });
  }

  /// Apply brokerage settings for enabled exchanges after master creation.
  ///
  /// Each exchange's setup is fully independent of every other exchange's —
  /// running them concurrently instead of one at a time cuts the total
  /// wait for creating a master down to roughly the slowest single
  /// exchange's round trip instead of the sum of all of them. See
  /// create_user_view.dart's matching fix for the full rationale (this was
  /// the confirmed dominant contributor to "account creation taking a long
  /// time" complaints).
  Future<void> _applyBrokerageSettings(String? masterId) async {
    if (masterId == null) return;
    final token = await SecureStorageService().getToken();
    final apiService = ApiService(backendUrl);
    await Future.wait(_exchangeAllow.keys.map((exchange) =>
        _applyBrokerageSettingsForExchange(
            masterId, exchange, token, apiService)));
  }

  Future<void> _applyBrokerageSettingsForExchange(String masterId,
      String exchange, String? token, ApiService apiService) async {
    try {
        if (!_exchangeAllow[exchange]!) return;

        final brkSettings = _brokerageSettings[exchange];
        if (brkSettings == null) return;

        final valueStr =
            (brkSettings['controller'] as TextEditingController).text.trim();
        if (valueStr.isEmpty) return;
        final value = double.tryParse(valueStr);
        if (value == null || value <= 0) return;

        final type = brkSettings['type'] as String;
        final apiExchange = exchange == 'GLOBAL' ? 'INDICES' : exchange;

        // Bulk-create ensures all instruments for this exchange have brokerage entries
        await apiService.post(
            '/admin/brokerage-settings/bulk-create',
            {
              'exchange_name': apiExchange,
              'type': type,
              'default_brk_value': value,
              'user_id': masterId,
            },
            token: token);

        final customized = _brokerageCustomized[exchange] ?? false;
        if (!customized) {
          // Flat path (default, unchanged): collapse every script in this
          // segment down to the one value the admin typed.
          final fetchRes = await apiService.get(
            '/admin/brokerage-settings/exchange/$apiExchange?type=${Uri.encodeComponent(type)}&limit=2000&user_id=$masterId',
            token: token,
          );
          if (fetchRes.statusCode == 200) {
            final body = jsonDecode(fetchRes.body);
            if (body['success'] == true) {
              final items = body['data']['items'] as List? ?? [];
              if (items.isNotEmpty) {
                final ids =
                    items.map<String>((i) => i['id'].toString()).toList();
                await apiService.put(
                    '/admin/brokerage-settings/bulk-update',
                    {
                      'ids': ids,
                      'brk_value': value,
                      'type': type,
                    },
                    token: token);
              }
            }
          }
          return;
        }

        // Customized path: fetch the freshly-created rows (now carrying
        // `category` per item) and split the update by category (NFO) or
        // by matching script_name to its own per-script controller (MCX)
        // instead of collapsing everything to one value.
        final fetchRes = await apiService.get(
          '/admin/brokerage-settings/exchange/$apiExchange?type=${Uri.encodeComponent(type)}&limit=2000&user_id=$masterId',
          token: token,
        );
        if (fetchRes.statusCode != 200) return;
        final body = jsonDecode(fetchRes.body);
        if (body['success'] != true) return;
        final items = List<Map<String, dynamic>>.from(body['data']['items'] ?? []);
        if (items.isEmpty) return;

        if (_categorySegments.contains(exchange)) {
          for (final category in ['INDEX', 'STOCK']) {
            final controller = category == 'INDEX'
                ? _indexBrkControllers[exchange]
                : _stockBrkControllers[exchange];
            final catValueStr = controller?.text.trim() ?? '';
            // A blank per-category field falls back to the flat field's own
            // value rather than discarding it — the flat field stays
            // editable even while this panel is expanded, so a master
            // naturally expects it to still apply. See create_user_view.dart's
            // matching fix for the confirmed-live repro of this bug.
            final catValue = catValueStr.isEmpty
                ? value
                : double.tryParse(catValueStr);
            if (catValue == null || catValue <= 0) continue;

            final ids = items
                .where((i) => i['category'] == category)
                .map<String>((i) => i['id'].toString())
                .toList();
            if (ids.isEmpty) continue;
            await apiService.put(
                '/admin/brokerage-settings/bulk-update',
                {
                  'ids': ids,
                  'brk_value': catValue,
                  'type': type,
                },
                token: token);
          }
        } else if (_perScriptSegments.contains(exchange)) {
          final scriptControllers = _scriptBrkControllers[exchange] ?? const {};
          // Group scripts by their entered value so scripts sharing a
          // value go in one bulk-update call instead of one call each.
          final idsByValue = <double, List<String>>{};
          for (final item in items) {
            final scriptName = item['script_name'] as String?;
            final controller = scriptControllers[scriptName];
            final scriptValueStr = controller?.text.trim() ?? '';
            // Same fallback as the category branch above.
            final scriptValue = scriptValueStr.isEmpty
                ? value
                : double.tryParse(scriptValueStr);
            if (scriptValue == null || scriptValue <= 0) continue;
            idsByValue.putIfAbsent(scriptValue, () => []).add(item['id'].toString());
          }
          for (final entry in idsByValue.entries) {
            await apiService.put(
                '/admin/brokerage-settings/bulk-update',
                {
                  'ids': entry.value,
                  'brk_value': entry.key,
                  'type': type,
                },
                token: token);
          }
        }
    } catch (e) {
      log('⚠️ Error applying brokerage settings for $exchange: $e');
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
                    widget.master != null ? 'Edit Master' : 'Create Master',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeViewTitle,
                      fontFamily: kFontFamily,
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
                            label: 'Investor Password',
                            controller: _investorPasswordController,
                            obscureText: true,
                            hint: 'Optional — read-only access',
                          ),
                          _divider(),
                          _buildTextField(
                            label: 'Confirm Investor',
                            controller: _confirmInvestorPasswordController,
                            obscureText: true,
                            hint: 'Optional',
                          ),
                          _divider(),
                          _buildTextField(
                              label: 'Credit',
                              controller: _creditController,
                              keyboardType: TextInputType.number,
                              showWordsInIndian: true,
                              remainingAvailable: Provider.of<
                                          UserProfileProvider>(context,
                                      listen: false)
                                  .master
                                  ?.equity),
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

                    // Allotted Script Quantity Groups (admin-only)
                    Consumer<UserProfileProvider>(
                      builder: (context, profile, _) {
                        if (!profile.isAdmin) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAllottedGroupsSection(),
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                    ),

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

                    // Brokerage Settings (inline)
                    _sectionLabel('BROKERAGE SETTINGS'),
                    const SizedBox(height: 12),
                    _card(
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text('Exchange',
                                      style: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: kFontSizeNavLabel,
                                          fontFamily: kFontFamily,
                                          fontWeight: kFontWeightSemiBold,
                                          letterSpacing: 0.5)),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Center(
                                    child: Text('Type',
                                        style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: kFontSizeNavLabel,
                                            fontFamily: kFontFamily,
                                            fontWeight: kFontWeightSemiBold,
                                            letterSpacing: 0.5)),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: Text('Value',
                                        style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: kFontSizeNavLabel,
                                            fontFamily: kFontFamily,
                                            fontWeight: kFontWeightSemiBold,
                                            letterSpacing: 0.5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ..._exchangeAllow.keys
                              .map((exchange) => _buildBrokerageRow(exchange)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Toggles
                    _card(
                      child: Column(
                        children: [
                          _buildToggleRow('Add Master', _addMaster,
                              (v) => setState(() => _addMaster = v)),
                          const SizedBox(height: 12),
                          _buildToggleRow(
                              'Reset Password on First Login',
                              _changePasswordOnFirstLogin,
                              (v) => setState(
                                  () => _changePasswordOnFirstLogin = v)),
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
                                    kBrandGradientStart,
                                    kBrandGradientEnd,
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
                                    fontFamily: kFontFamily,
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
        fontFamily: kFontFamily,
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
    bool showWordsInIndian = false,
    double? remainingAvailable,
  }) {
    final showRemainingHint = remainingAvailable != null;
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
                  label,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: kFontSizeBodySmall,
                    fontFamily: kFontFamily,
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
                  onChanged: (showWordsInIndian || showRemainingHint)
                      ? (_) => setState(() {})
                      : null,
                  style: readOnly
                      ? const TextStyle(color: Colors.grey)
                      : const TextStyle(
                          color: Colors.black,
                          fontSize: kFontSizeBody,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightMedium,
                        ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint ?? label,
                    hintStyle: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: kFontSizeBody,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightRegular,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          if (showWordsInIndian)
            Builder(builder: (_) {
              final parsed = double.tryParse(controller.text.trim());
              final words = numberToIndianWords(parsed);
              if (words.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 110, top: 2),
                child: Text(
                  '₹ $words',
                  style: const TextStyle(
                    color: kBrandPrimary,
                    fontSize: 11,
                    fontFamily: kFontFamily,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }),
          if (showRemainingHint)
            _remainingBalanceHint(remainingAvailable, controller.text),
        ],
      ),
    );
  }

  /// "Available X → Remaining Y" (or an explicit shortfall) shown under a
  /// credit/wallet input as the master types — computed against THIS
  /// master's own current balance so they can see what this allocation will
  /// leave before submitting, instead of finding out only from a rejected
  /// request. Mirrors the same hint added to the web portal's create-account
  /// forms.
  Widget _remainingBalanceHint(double available, String enteredText) {
    final entered = double.tryParse(enteredText.trim()) ?? 0;
    final remaining = available - entered;
    final negative = remaining < 0;
    final fmt = NumberFormat('#,##0.00');
    return Padding(
      padding: const EdgeInsets.only(left: 110, top: 2),
      child: Text(
        negative
            ? 'Exceeds available balance by ${fmt.format(remaining.abs())}'
            : 'Available ${fmt.format(available)} → Remaining ${fmt.format(remaining)}',
        style: TextStyle(
          color: negative ? const Color(0xFFEF4444) : kBrandPrimary,
          fontSize: 11,
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w500,
        ),
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
                fontFamily: kFontFamily,
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
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightRegular,
                  ),
                ),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down,
                    size: 18, color: Color(0xFF94A3B8)),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: kFontSizeBody,
                  fontFamily: kFontFamily,
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
                  fontFamily: kFontFamily,
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
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightMedium,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter value',
                    hintStyle: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: kFontSizeBody,
                        fontFamily: kFontFamily),
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
                        color: kBrandPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isMaster
                            ? 'Our: ${parentVal.toStringAsFixed(1)}'
                            : 'Our: 100',
                        style: const TextStyle(
                          color: kBrandPrimary,
                          fontSize: kFontSizeSubtitle,
                          fontFamily: kFontFamily,
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
                          fontFamily: kFontFamily,
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

  Widget _buildAllottedGroupsSection() {
    final activeExchanges =
        _exchangeAllow.entries.where((e) => e.value).map((e) => e.key).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('ALLOTTED SCRIPT QUANTITY GROUPS'),
        const SizedBox(height: 6),
        const Text(
          'Which group(s) this master may use for their own script quantity, '
          'and hand out to their clients. Leave an exchange unchecked to '
          'leave it unrestricted.',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: kFontSizeNavLabel,
            fontFamily: kFontFamily,
          ),
        ),
        const SizedBox(height: 12),
        if (activeExchanges.isEmpty)
          _card(
            child: Text(
              'Select an exchange above to allot groups.',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: kFontSizeBodySmall,
                fontFamily: kFontFamily,
              ),
            ),
          )
        else if (_isLoadingAvailableGroups)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: CircularProgressIndicator(
                    color: kBrandPrimary, strokeWidth: 2.5)),
          )
        else
          ...activeExchanges.map((exchange) {
            final available = _availableGroupsByExchange[exchange] ?? [];
            final selected = _allottedGroups[exchange] ?? <String>{};
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exchange,
                        style: const TextStyle(
                            color: kBrandPrimary,
                            fontSize: kFontSizeBodySmall,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold)),
                    const SizedBox(height: 8),
                    if (available.isEmpty)
                      const Text('No groups exist for this exchange yet.',
                          style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: kFontSizeNavLabel,
                              fontFamily: kFontFamily))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: available.map((groupName) {
                          final isSelected = selected.contains(groupName);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (isSelected) {
                                _allottedGroups[exchange]!.remove(groupName);
                              } else {
                                _allottedGroups[exchange]!.add(groupName);
                              }
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? kBrandPrimary
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? kBrandPrimary
                                      : const Color(0xFFF1F5F9),
                                ),
                              ),
                              child: Text(groupName,
                                  style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF64748B),
                                      fontSize: kFontSizeNavLabel,
                                      fontFamily: kFontFamily,
                                      fontWeight: kFontWeightSemiBold)),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
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
                  color: kBrandPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  values.values.every((v) => v) ? 'Deselect All' : 'Select All',
                  style: const TextStyle(
                    color: kBrandPrimary,
                    fontSize: kFontSizeNavLabel,
                    fontFamily: kFontFamily,
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
                        ? kBrandPrimary
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? kBrandPrimary
                          : const Color(0xFFF1F5F9),
                    ),
                  ),
                  child: Text(
                    key,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF64748B),
                      fontSize: kFontSizeBodySmall,
                      fontFamily: kFontFamily,
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

  // ── Brokerage row ──

  Widget _buildBrokerageRow(String exchange) {
    final settings = _brokerageSettings[exchange];
    if (settings == null) return const SizedBox.shrink();

    final type = settings['type'] as String;
    final controller = settings['controller'] as TextEditingController;
    final canCustomize = _categorySegments.contains(exchange) ||
        _perScriptSegments.contains(exchange);
    final customized = _brokerageCustomized[exchange] ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrokerageFlatRow(exchange, type, controller, canCustomize, customized),
          if (canCustomize && customized) _buildBrokerageCustomizePanel(exchange),
        ],
      ),
    );
  }

  Widget _buildBrokerageFlatRow(
    String exchange,
    String type,
    TextEditingController controller,
    bool canCustomize,
    bool customized,
  ) {
    return Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              exchange,
              style: const TextStyle(
                color: Colors.black,
                fontSize: kFontSizeBodySmall,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightMedium,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _brokerageSettings[exchange]!['type'] =
                      type == 'LOT WISE' ? 'TURNOVER WISE' : 'LOT WISE';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: type == 'LOT WISE'
                      ? kBrandPrimary.withValues(alpha: 0.08)
                      : const Color(0xFF10B981).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  type == 'LOT WISE' ? 'LOT' : 'T/O',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: type == 'LOT WISE'
                        ? kBrandPrimary
                        : const Color(0xFF10B981),
                    fontSize: kFontSizeCaption,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightSemiBold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: customized
                    ? const Color(0xFFEEF1F5)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: TextField(
                controller: controller,
                enabled: !customized,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  color: customized ? const Color(0xFF94A3B8) : Colors.black,
                  fontSize: kFontSizeBodySmall,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightMedium,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  hintText: '0',
                  hintStyle: TextStyle(
                      color: Color(0xFFCBD5E1), fontSize: kFontSizeBodySmall),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          if (canCustomize) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _toggleCustomizeBrokerage(exchange),
              child: Icon(
                customized ? Icons.expand_less : Icons.tune,
                size: 18,
                color: customized ? kBrandPrimary : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ],
    );
  }

  Widget _buildBrokerageCustomizePanel(String exchange) {
    if (_loadingScripts[exchange] == true) {
      return const Padding(
        padding: EdgeInsets.only(top: 8, left: 4),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final scripts = _segmentScripts[exchange] ?? const [];

    if (_categorySegments.contains(exchange)) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCategoryValueRow(exchange, 'INDEX', 'Index'),
            const SizedBox(height: 6),
            _buildCategoryValueRow(exchange, 'STOCK', 'Stock'),
          ],
        ),
      );
    }

    if (_perScriptSegments.contains(exchange)) {
      final controllers = _scriptBrkControllers[exchange] ?? const {};
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBulkApplyBar(exchange),
            for (final script in scripts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildScriptValueRow(
                  exchange,
                  script['raw_name'] as String,
                  controllers[script['raw_name']],
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildCategoryValueRow(String exchange, String category, String label) {
    final controller = _categoryController(exchange, category);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: kFontSizeCaption,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightMedium,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _brokerageValueField(controller),
        ),
      ],
    );
  }

  Widget _buildBulkApplyBar(String exchange) {
    final selectedCount = (_selectedScriptsForBulk[exchange] ?? const {}).length;
    final error = _bulkApplyError[exchange];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _brokerageValueField(_bulkScriptValueController(exchange))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _applyBulkScriptValue(exchange),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: kBrandPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Apply to selected ($selectedCount)',
                    style: const TextStyle(
                      color: kBrandPrimary,
                      fontSize: kFontSizeCaption,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightMedium,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error ?? 'Select scripts below, type a value, tap apply',
              style: TextStyle(
                color: error != null ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                fontSize: kFontSizeCaption,
                fontFamily: kFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptValueRow(String exchange, String rawName, TextEditingController? controller) {
    if (controller == null) return const SizedBox.shrink();
    final selected = _selectedScriptsForBulk[exchange] ?? const {};
    final checked = selected.contains(rawName);
    return Row(
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: Checkbox(
            value: checked,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              setState(() {
                final set = _selectedScriptsForBulk.putIfAbsent(exchange, () => {});
                if (v == true) {
                  set.add(rawName);
                } else {
                  set.remove(rawName);
                }
              });
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: Text(
            rawName,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: kFontSizeCaption,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightMedium,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _brokerageValueField(controller),
        ),
      ],
    );
  }

  Widget _brokerageValueField(TextEditingController controller) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(
          color: Colors.black,
          fontSize: kFontSizeCaption,
          fontFamily: kFontFamily,
          fontWeight: kFontWeightMedium,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: '0',
          hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeCaption),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
        ),
      ),
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
                        fontFamily: kFontFamily,
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
                      fontFamily: kFontFamily,
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
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightMedium),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: kFontSizeBody,
                        fontFamily: kFontFamily),
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
                  color: kBrandPrimary,
                  fontSize: 11,
                  fontFamily: kFontFamily,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }),
          Builder(builder: (_) {
            final master =
                Provider.of<UserProfileProvider>(context, listen: false)
                    .master;
            final available = master?.wallet[category];
            if (available == null) return const SizedBox.shrink();
            return _remainingBalanceHint(available, controller.text);
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
              fontFamily: kFontFamily,
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
                    value ? kBrandPrimary : const Color(0xFFCBD5E1),
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
