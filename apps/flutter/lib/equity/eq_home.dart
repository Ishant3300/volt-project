// Equity home — the whole equity app for an equity master or equity-only client, and
// the "Equity" screen admin opens from Profile. Its own API, socket and pages; the F&O
// providers (watchlist, metrics, profile) are never loaded here.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';
import 'eq_api.dart';
import 'eq_live.dart';
import 'eq_more.dart';
import 'eq_orders.dart';
import 'eq_portfolio.dart';
import 'eq_watchlist.dart';

class EquityHome extends StatefulWidget {
  /// Show the forced first-login password change first (equity accounts).
  final bool requiresPasswordChange;
  const EquityHome({super.key, this.requiresPasswordChange = false});

  @override
  State<EquityHome> createState() => _EquityHomeState();
}

class _EquityHomeState extends State<EquityHome> {
  String? _role;
  int _tab = 0;
  late final EqApi _api = EqApi(context.read<ApiService>());
  late final EqLive _live = EqLive(_api);
  late bool _mustChangePassword = widget.requiresPasswordChange;

  @override
  void initState() {
    super.initState();
    SecureStorageService().getRole().then((r) {
      if (mounted) setState(() => _role = (r ?? '').toUpperCase());
    });
    _live.start();
  }

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    return MultiProvider(
      providers: [
        Provider<EqApi>.value(value: _api),
        ChangeNotifierProvider<EqLive>.value(value: _live),
      ],
      child: Builder(builder: (context) {
        if (role == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (_mustChangePassword && isCashRole(role)) {
          return EqPasswordPage(forced: true, onDone: () => setState(() => _mustChangePassword = false));
        }
        final isManager = role != 'CASH_CLIENT';
        final pages = [
          EqWatchlistPage(isManager: isManager),
          EqPortfolioPage(isManager: isManager),
          EqOrdersPage(isManager: isManager),
          EqMorePage(role: role),
        ];
        return Scaffold(
          backgroundColor: kPageBg,
          appBar: AppBar(
            backgroundColor: kPageBg,
            title: Text(role == 'CASH_CLIENT' ? 'Equity' : role == 'CASH_MASTER' ? 'Equity · Master' : 'Equity · Admin',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            automaticallyImplyLeading: role == 'ADMIN',
          ),
          body: IndexedStack(index: _tab, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.list_alt), label: 'Watchlist'),
              NavigationDestination(icon: const Icon(Icons.pie_chart_outline), label: isManager ? 'Portfolio' : 'Holdings'),
              const NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Orders'),
              NavigationDestination(icon: const Icon(Icons.more_horiz), label: isManager ? 'Clients' : 'More'),
            ],
          ),
        );
      }),
    );
  }
}
