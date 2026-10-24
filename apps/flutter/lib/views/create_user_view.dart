import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:developer';
import '../utils/number_to_words.dart';
import '../utils/usual_brokerage.dart';
import '../utils/profit_book_minimum.dart';
import '../providers/user_profile_provider.dart';
import '../services/admin_service.dart';
import '../services/master_service.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../models/user.dart';
import '../models/master.dart';
import '../utils/contants.dart';
import '../utils/wallet_category.dart';
import '../widgets/create_for_master_picker.dart';

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
  final TextEditingController _investorPasswordController =
      TextEditingController();
  final TextEditingController _confirmInvestorPasswordController =
      TextEditingController();
  final TextEditingController _creditController = TextEditingController();
  // Profit book time (minutes) — mandatory; empty on a new client so the
  // creator always decides it (backend utils/profitBookTime.js).
  final TextEditingController _profitBookController = TextEditingController();
  // Admin minimum (default 5): a new client starts at it; a CHANGED time may
  // not go below it (backend utils/profitBookTime.js).
  int _profitBookMin = kDefaultProfitBookMinimum;

  Future<void> _loadProfitBookMinimum() async {
    final min = await fetchProfitBookMinimum();
    if (!mounted) return;
    setState(() {
      _profitBookMin = min;
      if (widget.user == null && _profitBookController.text.trim().isEmpty) {
        _profitBookController.text = min.toString();
      }
    });
  }
  final TextEditingController _noteController = TextEditingController();

  bool _marginSquareOff = false;
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

  String? _generatedUsername;
  bool _isSuccess = false;

  Map<String, Map<String, dynamic>> _exchangeSettings = {};
  Map<String, bool> _tradeLimit = {};
  Map<String, List<String>> _exchangeLotNames = {};

  List<String> _allowedExchanges = [];
  List<String> _allowedTradeLimit = [];

  // Brokerage settings per exchange (inline during creation)
  Map<String, Map<String, dynamic>> _brokerageSettings = {};
  // { 'NFO-FUT': { 'type': 'TURNOVER WISE', 'value': 0.02 }, ... }

  // The logged-in master's OWN rate per exchange — the real floor a new
  // client's flat brokerage can't be set below (mirrors the backend's own
  // enforceFloor/validateBrokerageFloor rejection in
  // brokerageCopyService.js). Populated once via _fetchOwnBrokerageFloor,
  // independent of whatever _brokerageSettings' own 'value' currently
  // shows (which the master then edits).
  final Map<String, double> _brokerageFloor = {};

  // "Create account for" (create mode): who owns AND funds the new client —
  // the logged-in master by default ("Myself"), or a master in their
  // downline (e.g. harry creating a client for his sub-master vijay); admin
  // must pick a master (any). Every owner-dependent
  // value (offered exchanges, trade limits, balance/wallet checks, P&L and
  // brokerage sharing, server, brokerage rates/floor) reads _ownerMaster,
  // never profileProvider.master directly. The backend (`for_master_id`)
  // enforces the same ownership.
  List<Map<String, dynamic>> _downlineMasters = [];
  Master? _forMaster;
  bool _loadingForMaster = false;

  Master? get _ownerMaster =>
      _forMaster ??
      Provider.of<UserProfileProvider>(context, listen: false).master;

  Future<void> _loadDownlineMasters() async {
    final isAdmin =
        Provider.of<UserProfileProvider>(context, listen: false).isAdmin;
    final list = await loadCreateForMasters(isAdmin: isAdmin);
    if (mounted) setState(() => _downlineMasters = list);
  }

  /// null = back to the logged-in master. Otherwise loads that master's full
  /// record (balance, wallet, sharing, server, exchanges) and re-derives the
  /// whole form from it.
  Future<void> _selectForMaster(String? masterId) async {
    if (masterId == null) {
      setState(() => _forMaster = null);
      _reloadForOwner();
      return;
    }
    setState(() => _loadingForMaster = true);
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl)
          .get('/master/masters/$masterId', token: token);
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true && mounted) {
        setState(() => _forMaster = Master.fromJson(body['data']));
        _reloadForOwner();
      } else if (mounted) {
        _showSnack(body['message'] ?? 'Could not load that master',
            isError: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Could not load that master', isError: true);
    } finally {
      if (mounted) setState(() => _loadingForMaster = false);
    }
  }

  /// Everything owner-dependent is re-derived for the new owner: allowed
  /// exchanges/trade limits, brokerage rows and their floor.
  void _reloadForOwner() {
    setState(() {
      _brokerageFloor.clear();
      _brokerageCustomized.clear();
    });
    _loadMasterPermissions();
  }

  // Trade Wallet inputs per allowed category (NSE/MCX/GLOBAL)
  final Map<String, TextEditingController> _walletControllers = {};

  void _generateUsername() async {
    try {
      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      final apiService = Provider.of<ApiService>(context, listen: false);
      final res = profileProvider.isAdmin
          ? await AdminService(apiService).generateUsername()
          : await MasterService(apiService).generateUsername();

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
        final profileProvider =
            Provider.of<UserProfileProvider>(context, listen: false);
        final apiService = Provider.of<ApiService>(context, listen: false);
        if (profileProvider.isAdmin) {
          await AdminService(apiService).releaseUsername(_generatedUsername!);
        } else {
          await MasterService(apiService).releaseUsername(_generatedUsername!);
        }
      } catch (e) {
        log('Error releasing username: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMasterPermissions();
    _loadProfitBookMinimum();

    if (widget.user != null) {
      _nameController.text = widget.user!.name;
      _usernameController.text = widget.user!.username;
      _creditController.text = widget.user!.credits.toString();
      _profitBookController.text =
          (widget.user!.profitBookMinutes ?? kDefaultProfitBookMinimum).toString();
      _noteController.text = widget.user!.note;
      _marginSquareOff = widget.user!.marginSquareOff;
      _changePasswordOnFirstLogin = widget.user!.changePassOnFirstLogin;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _generateUsername());
      final profile = Provider.of<UserProfileProvider>(context, listen: false);
      if (profile.isMaster || profile.isAdmin) {
        _loadDownlineMasters();
      }
    }
  }

  void _loadMasterPermissions() async {
    final profileProvider =
        Provider.of<UserProfileProvider>(context, listen: false);
    final adminService = Provider.of<AdminService>(context, listen: false);

    // Determine which master's permissions to use for the exchange list.
    // - If logged in as master: use their own permissions.
    // - If logged in as admin editing a user: fetch the user's parent master's permissions.
    List<String>? masterExchanges;
    List<String>? masterTradeLimit;

    final owner = _ownerMaster;
    if (owner != null) {
      masterExchanges = owner.exchangesAllowed
          .map((ex) => ex == 'INDICES' ? 'GLOBAL' : ex)
          .toList();
      masterTradeLimit = owner.tradeLimit
          .map((ex) => ex == 'INDICES' ? 'GLOBAL' : ex)
          .toList();
    } else if (profileProvider.isAdmin && widget.user != null) {
      // Admin editing user: get exchanges from the user's parent master
      try {
        final token = await SecureStorageService().getToken();
        final apiService = ApiService(backendUrl);
        final masterId = widget.user!.masterId;
        if (masterId != null && masterId.isNotEmpty) {
          final res =
              await apiService.get('/master/masters/$masterId', token: token);
          if (res.statusCode == 200) {
            final body = jsonDecode(res.body);
            final masterData = body['data'];
            if (masterData != null) {
              final List exList = masterData['exchanges_allowed'] ?? [];
              masterExchanges = exList
                  .map<String>((e) =>
                      (e is String ? e : e.toString()) == 'INDICES'
                          ? 'GLOBAL'
                          : (e is String ? e : e.toString()))
                  .toList();
              final List tlList = masterData['trade_limit'] ?? [];
              masterTradeLimit = tlList
                  .map<String>((e) =>
                      (e is String ? e : e.toString()) == 'INDICES'
                          ? 'GLOBAL'
                          : (e is String ? e : e.toString()))
                  .toList();
            }
          }
        }
      } catch (e) {
        log('⚠️ Error fetching parent master permissions: $e');
      }

      // Fallback for admin: if we couldn't get master data, show all standard exchanges
      if (masterExchanges == null || masterExchanges!.isEmpty) {
        masterExchanges = [
          'NFO-FUT',
          'NFO-OPT',
          'MCX-FUT',
          'MCX-OPT',
          'GLOBAL',
          'COMEX-FUT'
        ];
        masterTradeLimit = [
          'NFO-FUT',
          'NFO-OPT',
          'MCX-FUT',
          'MCX-OPT',
          'GLOBAL',
          'COMEX-FUT'
        ];
      }
    }

    if (masterExchanges != null && masterExchanges!.isNotEmpty) {
      setState(() {
        _allowedExchanges = masterExchanges!;
        _allowedTradeLimit = masterTradeLimit ?? masterExchanges!;

        _exchangeSettings = {};
        for (var exchange in _allowedExchanges) {
          _exchangeSettings[exchange] = {
            'enabled': false,
            'turnover': false,
            'lot': false,
            'group': null,
          };
        }

        // Initialize brokerage settings with sensible defaults per exchange
        _brokerageSettings = {};
        for (var exchange in _allowedExchanges) {
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

      // Pre-fetch current brokerage values for display
      _fetchCurrentBrokerage();
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
          final names = List<String>.from(data['data']);
          setState(() {
            _exchangeLotNames[exchange] = names;
            // Auto-select 'GOLDMIN' group when creating a new user (not editing)
            if (widget.user == null &&
                _exchangeSettings[exchange] != null &&
                _exchangeSettings[exchange]!['group'] == null &&
                names.contains('GOLDMIN')) {
              _exchangeSettings[exchange]!['group'] = 'GOLDMIN';
            }
          });
        }
      }
    } catch (e) {
      log('❌ Error fetching lot names for $exchange: $e');
    }
  }

  /// Fetch current brokerage values for each exchange to pre-fill the inline
  /// section. When editing an existing user, scoped to THEIR user_id (shows
  /// what they're already charged). When creating a new user, this used to
  /// omit user_id entirely — silently pulling the shared GLOBAL default
  /// instead of the logged-in master's own rate, so a master who had
  /// already overridden their own rate above the global default got a
  /// prefilled value their new client would immediately fail the backend's
  /// floor check against. Now scoped to the logged-in master's own id in
  /// that case, same source _fetchOwnBrokerageFloor below uses.
  Future<void> _fetchCurrentBrokerage() async {
    // Read BEFORE the first await below — Provider.of needs a still-valid
    // context, and this method has no mounted guard until its own setState
    // calls further down.
    final ownMasterId = widget.user == null ? _ownerMaster?.id : null;
    try {
      final token = await SecureStorageService().getToken();
      final apiService = ApiService(backendUrl);
      final userId = widget.user?.id ?? ownMasterId;

      for (final exchange in _allowedExchanges) {
        final apiExchange = exchange == 'GLOBAL' ? 'INDICES' : exchange;
        final brkSettings = _brokerageSettings[exchange];
        if (brkSettings == null) continue;

        final type = brkSettings['type'] as String;
        final userQuery = userId != null ? '&user_id=$userId' : '';
        final res = await apiService.get(
          '/admin/brokerage-settings/exchange/$apiExchange?type=${Uri.encodeComponent(type)}&limit=2000$userQuery',
          token: token,
        );
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body['success'] == true) {
            final items = body['data']['items'] as List? ?? [];
            if (items.isNotEmpty) {
              // The usual rate, not the first row (see usualBrokerage).
              final firstVal = usualBrokerage(items) ?? 0;
              if (mounted) {
                setState(() {
                  brkSettings['value'] = firstVal.toString();
                  (brkSettings['controller'] as TextEditingController).text =
                      firstVal % 1 == 0
                          ? firstVal.toInt().toString()
                          : firstVal.toString();
                  // Creating (not editing) means this fetched value IS the
                  // master's own rate — capture it as the floor too, since
                  // the field above is about to become editable.
                  if (widget.user == null) {
                    _brokerageFloor[exchange] = firstVal;
                  }
                });
              }
            }
          }
        }
      }
    } catch (e) {
      log('⚠️ Error fetching current brokerage: \$e');
    }
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
  /// clears the selection so the next batch starts fresh. Validates the
  /// same way the rest of this form does (see the empty-state error pattern
  /// used elsewhere): a clear inline message, no silent no-op.
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

  /// Apply brokerage settings for enabled exchanges after user creation.
  ///
  /// Each exchange's setup (its own bulk-create + bulk-update calls, scoped
  /// to that exchange_name) is fully independent of every other exchange's
  /// — there was no reason they were awaited one at a time other than that
  /// being the easiest way to write the loop. With every exchange enabled
  /// (now 6, incl. COMEX-FUT/GLOBAL) that meant up to ~15+ sequential
  /// network round trips to create one user, each paying full latency
  /// before the next could even start — confirmed as the dominant
  /// contributor to "account creation taking a long time" complaints.
  /// Running them concurrently via Future.wait cuts the total wait down to
  /// roughly the slowest single exchange's round trip instead of the sum
  /// of all of them.
  Future<void> _applyBrokerageSettings(String? userId) async {
    final token = await SecureStorageService().getToken();
    final apiService = ApiService(backendUrl);
    await Future.wait(_allowedExchanges.map((exchange) =>
        _applyBrokerageSettingsForExchange(userId, exchange, token, apiService)));
  }

  Future<void> _applyBrokerageSettingsForExchange(String? userId,
      String exchange, String? token, ApiService apiService) async {
    try {
        // Only apply for enabled exchanges
        if (_exchangeSettings[exchange]?['enabled'] != true) return;

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
            'user_id': userId,
          },
          token: token,
        );

        final userQuery = userId != null ? '&user_id=$userId' : '';
        final customized = _brokerageCustomized[exchange] ?? false;
        if (!customized) {
          // Flat path (default, unchanged): collapse every script in this
          // segment down to the one value the admin typed.
          final fetchRes = await apiService.get(
            '/admin/brokerage-settings/exchange/$apiExchange?type=${Uri.encodeComponent(type)}&limit=2000$userQuery',
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
                  token: token,
                );
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
          '/admin/brokerage-settings/exchange/$apiExchange?type=${Uri.encodeComponent(type)}&limit=2000$userQuery',
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
            // A blank per-category field is NOT "leave unset" — the flat
            // field above stays visible and editable even while this panel
            // is expanded, and a master naturally expects it to still be
            // the value that applies. Previously this `continue`d, silently
            // discarding whatever was typed into the flat field for any
            // category whose own override was left blank — confirmed live
            // (801351, MCX-FUT): the per-script panel was open, no script
            // was individually overridden, and the flat field's edit never
            // reached the backend at all.
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
              token: token,
            );
          }
        } else if (_perScriptSegments.contains(exchange)) {
          final scriptControllers = _scriptBrkControllers[exchange] ?? const {};
          final idsByValue = <double, List<String>>{};
          for (final item in items) {
            final scriptName = item['script_name'] as String?;
            final controller = scriptControllers[scriptName];
            final scriptValueStr = controller?.text.trim() ?? '';
            // Same fallback as the category branch above — a script left
            // blank in the per-script panel still gets the flat field's
            // value, not silence.
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
              token: token,
            );
          }
        }
    } catch (e) {
      log('⚠️ Error applying brokerage settings for $exchange: $e');
    }
  }

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
    _profitBookController.dispose();
    _noteController.dispose();
    for (final entry in _brokerageSettings.values) {
      (entry['controller'] as TextEditingController?)?.dispose();
    }
    for (final controller in _walletControllers.values) {
      controller.dispose();
    }
    for (final controller in _bulkScriptValueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Exchange/segment names currently selected in the form (for exchanges_allowed).
  List<String> get _selectedExchangeNames => _exchangeSettings.entries
      .where((e) => e.value['enabled'] == true)
      .map((e) => e.key)
      .toList();

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

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? kColorSell : kColorBuy,
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

    final credit = double.tryParse(_creditController.text.trim());
    if (credit == null || credit < 0) {
      _showSnack('Please enter a valid credit amount', isError: true);
      return;
    }

    final profitBookMinutes = int.tryParse(_profitBookController.text.trim());
    if (profitBookMinutes == null ||
        profitBookMinutes < 0 ||
        profitBookMinutes > 1440) {
      _showSnack('Enter the profit book time in whole minutes (0–1440).',
          isError: true);
      return;
    }
    if (profitBookMinutes < _profitBookMin &&
        profitBookMinutes != widget.user?.profitBookMinutes) {
      _showSnack(
          'Profit book time cannot be less than $_profitBookMin minutes (admin minimum).',
          isError: true);
      return;
    }

    final profileProvider =
        Provider.of<UserProfileProvider>(context, listen: false);

    // Admin creating a client: it must belong to a master (picked above).
    if (profileProvider.isAdmin && widget.user == null && _forMaster == null) {
      _showSnack('Select the master this account belongs to', isError: true);
      return;
    }
    // Only require master if we are NOT an admin
    if (profileProvider.master == null && !profileProvider.isAdmin) {
      _showSnack('Master profile not found', isError: true);
      return;
    }

    // Own-balance guard: a master can't hand out more credit/wallet than
    // they themselves currently have — same checks the backend itself
    // enforces (parentMaster.equity < credits / walletService.block), just
    // surfaced here before the request instead of after a rejection.
    final ownMaster =
        widget.user == null ? _ownerMaster : profileProvider.master;
    final whose =
        _forMaster != null ? "${_forMaster!.username}'s" : 'your own';
    if (ownMaster != null) {
      if (credit > ownMaster.equity) {
        _showSnack(
            'Opening credit exceeds $whose available balance (${ownMaster.equity.toStringAsFixed(2)}).',
            isError: true);
        return;
      }
      for (final category in allowedCategories(_selectedExchangeNames)) {
        final entered =
            double.tryParse(_walletControllerFor(category).text.trim()) ?? 0;
        final available = ownMaster.wallet[category] ?? 0;
        if (entered > available) {
          _showSnack(
              '${walletLabel(category)} wallet amount exceeds $whose available balance (${available.toStringAsFixed(2)}).',
              isError: true);
          return;
        }
      }
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

    // Validate: each enabled exchange must have either Turnover or Lot selected
    for (final ex in exchangesAllowed) {
      final name = ex['exchange_name'] as String;
      final hasTurnover = ex['turnover'] == true;
      final hasLot = ex['lot'] == true;
      if (!hasTurnover && !hasLot) {
        _showSnack('Select either T/O or Lot for $name', isError: true);
        return;
      }
    }

    List<String> tradeLimitList = [];
    _tradeLimit.forEach((exchange, enabled) {
      if (enabled) tradeLimitList.add(exchange.toUpperCase());
    });

    // Floor check — mirrors the backend's own enforceFloor/
    // validateBrokerageFloor rejection (brokerageCopyService.js), surfaced
    // here before the request instead of after a failed submit. Only
    // covers the flat per-exchange rate (not the per-script/per-category
    // "Customize" sub-fields, which don't have their own floor hint here
    // yet — same gap the web portal had before those were wired up).
    if (widget.user == null) {
      for (final exchange in _allowedExchanges) {
        if (_exchangeSettings[exchange]?['enabled'] != true) continue;
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
      final adminService = Provider.of<AdminService>(context, listen: false);
      http.Response response;

      if (widget.user != null) {
        final walletMap =
            _buildWalletMap(allowedCategories(_selectedExchangeNames));
        response = await adminService.updateUser(
          userId: widget.user!.id,
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          investorPassword: _investorPasswordController.text.isNotEmpty
              ? _investorPasswordController.text
              : (widget.user != null ? null : ''),
          credits: credit,
          note: _noteController.text.trim().isEmpty
              ? ''
              : _noteController.text.trim(),
          pnlSharing:
              profileProvider.master?.pnlSharing ?? widget.user!.pnlSharing,
          brokerageSharing: profileProvider.master?.brokerageSharing ??
              widget.user!.brokerageSharing,
          exchangesAllowed: exchangesAllowed,
          tradeLimit: tradeLimitList,
          marginSquareOff: _marginSquareOff,
          changePassOnFirstLogin: _changePasswordOnFirstLogin,
          wallet: walletMap.isEmpty ? null : walletMap,
          profitBookMinutes: profitBookMinutes,
        );
      } else {
        // Initial Trade Wallet funding (optional; only for allowed categories).
        final walletMap =
            _buildWalletMap(allowedCategories(_selectedExchangeNames));
        response = await adminService.createUser(
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          investorPassword: _investorPasswordController.text.isNotEmpty
              ? _investorPasswordController.text
              : null,
          credits: credit,
          note: _noteController.text.trim().isEmpty
              ? ''
              : _noteController.text.trim(),
          pnlSharing: _ownerMaster!.pnlSharing,
          brokerageSharing: _ownerMaster!.brokerageSharing,
          exchangesAllowed: exchangesAllowed,
          tradeLimit: tradeLimitList,
          marginSquareOff: _marginSquareOff,
          changePassOnFirstLogin: _changePasswordOnFirstLogin,
          serverId: _ownerMaster!.serverId,
          profitBookMinutes: profitBookMinutes,
          forMasterId: _forMaster?.id,
          wallet: walletMap.isEmpty ? null : walletMap,
        );
      }

      if (!mounted) return;
      final data = jsonDecode(response.body);

      if ((response.statusCode == 201 || response.statusCode == 200) &&
          data['success'] == true) {
        _isSuccess = true;
        // Extract user_id: for new users from response data, for edits from widget
        final createdUserId = widget.user?.id ??
            data['data']?['id']?.toString() ??
            data['data']?['_id']?.toString();
        // Apply brokerage settings for enabled exchanges (scoped to this user)
        await _applyBrokerageSettings(createdUserId);

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
                          color: kColorTextPrimary, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.user != null ? 'Edit User' : 'Create User',
                    style: const TextStyle(
                      color: kColorTextPrimary,
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
                    if (widget.user == null) ...[
                      _sectionLabel('USER SELECTION'),
                      const SizedBox(height: 12),
                      _card(child: _buildCreateForPicker()),
                      const SizedBox(height: 20),
                    ],
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
                              readOnly: widget.user != null ||
                                  _generatedUsername != null),
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
                              label: 'Investor Password',
                              controller: _investorPasswordController,
                              obscureText: true),
                          _divider(),
                          _buildTextField(
                              label: 'Confirm Investor',
                              controller: _confirmInvestorPasswordController,
                              obscureText: true),
                          _divider(),
                          _buildTextField(
                              label: 'Credit',
                              controller: _creditController,
                              keyboardType: TextInputType.number,
                              showWordsInIndian: true,
                              remainingAvailable: _ownerMaster?.equity),
                          _divider(),
                          _buildTextField(
                              label: 'Profit Book (min) *',
                              controller: _profitBookController,
                              keyboardType: TextInputType.number),
                          Padding(
                            padding: const EdgeInsets.only(left: 100, bottom: 6),
                            child: Text(
                              "Can't close in profit until this long after opening; a loss can be closed any time. Minimum $_profitBookMin min (set by admin).",
                              style: const TextStyle(
                                  color: kColorTextMuted,
                                  fontSize: 11,
                                  fontFamily: kFontFamily),
                            ),
                          ),
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
                              color: kBrandPrimary
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _exchangeSettings.values
                                      .every((v) => v['enabled'])
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: const TextStyle(
                                  color: kBrandPrimary,
                                  fontSize: kFontSizeNavLabel,
                                  fontFamily: kFontFamily,
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
                                    color: kColorTextMuted,
                                    fontSize: kFontSizeBodySmall,
                                    fontFamily: kFontFamily)),
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
                                                  color: kColorTextMuted,
                                                  fontSize: kFontSizeNavLabel,
                                                  fontFamily: kFontFamily,
                                                  fontWeight:
                                                      kFontWeightSemiBold,
                                                  letterSpacing: 0.5)))),
                                  Expanded(
                                      flex: 1,
                                      child: Center(
                                          child: Text('T/O',
                                              style: TextStyle(
                                                  color: kColorTextMuted,
                                                  fontSize: kFontSizeNavLabel,
                                                  fontFamily: kFontFamily,
                                                  fontWeight:
                                                      kFontWeightSemiBold,
                                                  letterSpacing: 0.5)))),
                                  Expanded(
                                      flex: 1,
                                      child: Center(
                                          child: Text('Lot',
                                              style: TextStyle(
                                                  color: kColorTextMuted,
                                                  fontSize: kFontSizeNavLabel,
                                                  fontFamily: kFontFamily,
                                                  fontWeight:
                                                      kFontWeightSemiBold,
                                                  letterSpacing: 0.5)))),
                                  SizedBox(
                                      width: 130,
                                      child: Center(
                                          child: Text('Group',
                                              style: TextStyle(
                                                  color: kColorTextMuted,
                                                  fontSize: kFontSizeNavLabel,
                                                  fontFamily: kFontFamily,
                                                  fontWeight:
                                                      kFontWeightSemiBold,
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
                              color: kBrandPrimary
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _tradeLimit.values.every((v) => v)
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: const TextStyle(
                                  color: kBrandPrimary,
                                  fontSize: kFontSizeNavLabel,
                                  fontFamily: kFontFamily,
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
                                    color: kColorTextMuted,
                                    fontSize: kFontSizeBodySmall,
                                    fontFamily: kFontFamily)),
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
                                      ? kBrandPrimary
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: selected
                                          ? kBrandPrimary
                                          : const Color(0xFFF1F5F9)),
                                ),
                                child: Text(
                                  key,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF64748B),
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

                    const SizedBox(height: 24),

                    // Brokerage Settings (inline)
                    _sectionLabel('BROKERAGE SETTINGS'),
                    const SizedBox(height: 12),
                    _card(
                      child: Column(
                        children: [
                          // Header row
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text('Exchange',
                                      style: TextStyle(
                                          color: kColorTextMuted,
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
                                            color: kColorTextMuted,
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
                                            color: kColorTextMuted,
                                            fontSize: kFontSizeNavLabel,
                                            fontFamily: kFontFamily,
                                            fontWeight: kFontWeightSemiBold,
                                            letterSpacing: 0.5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ..._allowedExchanges
                              .map((exchange) => _buildBrokerageRow(exchange)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Trade Wallet
                    _buildWalletSection(),

                    const SizedBox(height: 24),

                    // Toggles
                    _card(
                      child: Column(
                        children: [
                          _buildToggleRow('Margin Square Off', _marginSquareOff,
                              (v) => setState(() => _marginSquareOff = v)),
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
                                    kBrandGradientStart,
                                    kBrandGradientEnd,
                                  ],
                                ),
                          color: _isSubmitting ? kColorTextMuted : null,
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
                                      fontFamily: kFontFamily,
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
        color: kColorTextMuted,
        fontSize: kFontSizeNavLabel,
        fontFamily: kFontFamily,
        fontWeight: kFontWeightSemiBold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildCreateForPicker() {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    final me = profile.master;
    return CreateForMasterPicker(
      masters: _downlineMasters,
      selectedId: _forMaster?.id,
      // Admin can't own a client — they must pick a master.
      selfLabel: profile.isAdmin || me == null
          ? null
          : 'Myself — ${me.name} (${me.username})',
      loading: _loadingForMaster,
      onSelect: _selectForMaster,
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
                width: 100,
                child: Text(
                  label,
                  style: const TextStyle(
                      color: kColorTextMuted,
                      fontSize: kFontSizeBodySmall,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightMedium),
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
                          color: kColorTextPrimary,
                          fontSize: kFontSizeBody,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightMedium,
                        ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: label,
                    hintStyle: const TextStyle(
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
          if (showWordsInIndian)
            Builder(builder: (_) {
              final parsed = double.tryParse(controller.text.trim());
              final words = numberToIndianWords(parsed);
              if (words.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 100, top: 2),
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
      padding: const EdgeInsets.only(left: 100, top: 2),
      child: Text(
        negative
            ? 'Exceeds available balance by ${fmt.format(remaining.abs())}'
            : 'Available ${fmt.format(available)} → Remaining ${fmt.format(remaining)}',
        style: TextStyle(
          color: negative ? kColorSell : kBrandPrimary,
          fontSize: 11,
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildExchangeRow(String exchange, Map<String, dynamic> settings) {
    final enabled = settings['enabled'] as bool;
    final ex = exchange.toUpperCase();

    // NFO-FUT, SGX, GLOBAL → block Lot checkbox (turnover-only exchanges)
    final bool lotBlocked = ex == 'NFO-FUT' || ex == 'GLOBAL';
    // NFO-OPT → block T/O checkbox (lot-only exchange)
    final bool toBlocked = ex == 'NFO-OPT';
    // MCX-FUT, MCX-OPT → mutually exclusive (only one can be selected)
    final bool mutuallyExclusive = ex == 'MCX-FUT' || ex == 'MCX-OPT';

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
                        enabled ? kBrandPrimary : Colors.transparent,
                    border: Border.all(
                        color: enabled
                            ? kBrandPrimary
                            : const Color(0xFFCBD5E1),
                        width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: enabled
                      ? const Icon(Icons.check,
                          color: Colors.white, size: kIconSizeSmall)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(exchange,
                      style: const TextStyle(
                          color: kColorTextPrimary,
                          fontSize: kFontSizeBodySmall,
                          fontFamily: kFontFamily,
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
                : () => setState(() {
                      settings['turnover'] = !(settings['turnover'] as bool);
                      // MCX: mutually exclusive — deselect Lot when T/O selected
                      if (mutuallyExclusive && settings['turnover'] == true) {
                        settings['lot'] = false;
                      }
                    }),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: toBlocked
                      ? const Color(0xFFE2E8F0)
                      : (settings['turnover'] as bool)
                          ? kBrandPrimary
                          : Colors.transparent,
                  border: Border.all(
                      color: toBlocked
                          ? const Color(0xFFE2E8F0)
                          : (settings['turnover'] as bool)
                              ? kBrandPrimary
                              : const Color(0xFFCBD5E1),
                      width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: (settings['turnover'] as bool) && !toBlocked
                    ? const Icon(Icons.check,
                        color: Colors.white, size: kIconSizeSmall)
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
                : () => setState(() {
                      settings['lot'] = !(settings['lot'] as bool);
                      // MCX: mutually exclusive — deselect T/O when Lot selected
                      if (mutuallyExclusive && settings['lot'] == true) {
                        settings['turnover'] = false;
                      }
                    }),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: lotBlocked
                      ? const Color(0xFFE2E8F0)
                      : (settings['lot'] as bool)
                          ? kBrandPrimary
                          : Colors.transparent,
                  border: Border.all(
                      color: lotBlocked
                          ? const Color(0xFFE2E8F0)
                          : (settings['lot'] as bool)
                              ? kBrandPrimary
                              : const Color(0xFFCBD5E1),
                      width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: (settings['lot'] as bool) && !lotBlocked
                    ? const Icon(Icons.check,
                        color: Colors.white, size: kIconSizeSmall)
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
                      fontFamily: kFontFamily),
                ),
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down,
                    size: kIconSizeDefault, color: kColorTextMuted),
                style: const TextStyle(
                    color: kColorTextPrimary,
                    fontSize: kFontSizeSubtitle,
                    fontFamily: kFontFamily,
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
                    color: kColorTextPrimary,
                    fontSize: kFontSizeBody,
                    fontFamily: kFontFamily,
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
                      color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ],
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
                        color: kColorTextMuted,
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
                width: 100,
                child: Text(
                  walletLabel(category),
                  style: const TextStyle(
                      color: kColorTextMuted,
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
                      color: kColorTextPrimary,
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
              padding: const EdgeInsets.only(left: 100, top: 2),
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
            final available = _ownerMaster?.wallet[category];
            if (available == null) return const SizedBox.shrink();
            return _remainingBalanceHint(available, controller.text);
          }),
        ],
      ),
    );
  }

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
          // Exchange name
          Expanded(
            flex: 3,
            child: Text(
              exchange,
              style: const TextStyle(
                color: kColorTextPrimary,
                fontSize: kFontSizeBodySmall,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightMedium,
              ),
            ),
          ),
          // Type toggle
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
                      : kColorBuy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  type == 'LOT WISE' ? 'LOT' : 'T/O',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: type == 'LOT WISE'
                        ? kBrandPrimary
                        : kColorBuy,
                    fontSize: kFontSizeCaption,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightSemiBold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Value input
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
                  color: customized ? kColorTextMuted : kColorTextPrimary,
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
                color: customized ? kBrandPrimary : kColorTextMuted,
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
              color: kColorTextMuted,
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
                color: error != null ? kColorSell : kColorTextMuted,
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
              color: kColorTextMuted,
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
          color: kColorTextPrimary,
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
}
