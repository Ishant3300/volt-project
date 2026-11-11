import 'package:flutter/material.dart';

import '../config/practice_session.dart';
import '../services/broker_service.dart';
import '../utils/contants.dart';

/// "Add broker" inside the Create Client / Create Master forms (owner,
/// 12 Nov 2026). TRACKING ONLY — the broker link is saved after the account
/// exists; nothing here changes the account's brokerage, the ledger or
/// settlement.
///
/// Shown only where this login may link the new account to a broker:
///   admin   — when the paying master (the new client's master, or the new
///             sub-master's parent) has "Brokers allowed";
///   master  — when admin allowed him, for his own DIRECT client / sub-master.
/// The broker's rate sits beside the client's rate in Brokerage Settings
/// (and in Customize: Index / Stock for NFO, per script for MCX). Each box
/// shows its room: on every script it covers, the new account's rate minus
/// the paying master's own rate — the same rule the server checks.

const List<String> kBrokerCategories = ['INDEX', 'STOCK'];

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

class NewAccountBrokerDraft {
  bool allowed = false; // this login may add a broker to this new account
  bool enabled = false; // the "Add broker" switch
  bool loadingBrokers = false;
  List<Map<String, dynamic>> brokers = [];
  String brokerId = ''; // '' | broker id | 'new'
  final TextEditingController newName = TextEditingController();
  final TextEditingController pnl = TextEditingController();
  final TextEditingController brk = TextEditingController();
  final Map<String, TextEditingController> _flat = {};
  final Map<String, Map<String, TextEditingController>> _category = {};
  final Map<String, Map<String, TextEditingController>> _script = {};
  final Map<String, TextEditingController> _bulk = {};

  bool get on => allowed && enabled;

  TextEditingController flat(String exchange) => _flat.putIfAbsent(exchange, () => TextEditingController());
  TextEditingController category(String exchange, String cat) =>
      _category.putIfAbsent(exchange, () => {}).putIfAbsent(cat, () => TextEditingController());
  TextEditingController script(String exchange, String name) =>
      _script.putIfAbsent(exchange, () => {}).putIfAbsent(name, () => TextEditingController());
  TextEditingController bulk(String exchange) => _bulk.putIfAbsent(exchange, () => TextEditingController());

  static double? read(TextEditingController? c) {
    final t = c?.text.trim() ?? '';
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  /// The rates for the server. `typeOf(exchange)` = the account's brokerage
  /// type there; `customizedCategory` / `customizedScript` say which panels
  /// are open (a closed panel's broker boxes are ignored, like the client's).
  List<Map<String, dynamic>> rates({
    required Iterable<String> exchanges,
    required String Function(String exchange) typeOf,
    required bool Function(String exchange) customizedCategory,
    required bool Function(String exchange) customizedScript,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final ex in exchanges) {
      final type = typeOf(ex);
      final f = read(_flat[ex]);
      if (f != null && f > 0) out.add({'segment': ex, 'type': type, 'value': f});
      if (customizedCategory(ex)) {
        for (final cat in kBrokerCategories) {
          final v = read(_category[ex]?[cat]);
          if (v != null && v > 0) out.add({'segment': ex, 'type': type, 'value': v, 'category': cat});
        }
      }
      if (customizedScript(ex)) {
        for (final e in (_script[ex] ?? const <String, TextEditingController>{}).entries) {
          final v = read(e.value);
          if (v != null && v > 0) out.add({'segment': ex, 'type': type, 'value': v, 'script': e.key});
        }
      }
    }
    return out;
  }

  void dispose() {
    newName.dispose();
    pnl.dispose();
    brk.dispose();
    for (final c in [..._flat.values, ..._bulk.values, for (final m in _category.values) ...m.values, for (final m in _script.values) ...m.values]) {
      c.dispose();
    }
  }
}

/// Whether this login may add a broker to a new account whose paying master is
/// `payingMasterId` (admin), or to his own direct account (master: `direct`).
Future<bool> brokerAllowedForNewAccount({required bool isAdmin, String? payingMasterId, required bool direct}) async {
  if (PracticeSession.isActive) return false;
  try {
    if (isAdmin) {
      if (payingMasterId == null || payingMasterId.isEmpty) return false;
      return await BrokerService(isAdmin: true).masterAllowed(payingMasterId);
    }
    if (!direct) return false;
    return await BrokerService(isAdmin: false).allowed();
  } catch (_) {
    return false;
  }
}

/// The broker's room on a set of scripts: the smallest (account rate −
/// paying master's own rate). `payingRows` = the paying master's own rows of
/// this exchange (script_name, brk_value, category); `accountRate` gives the
/// new account's rate for a script (its Customize value, else its flat value).
/// null = unknown (no rows loaded) — the server checks it then.
double? brokerRoom(
  List<Map<String, dynamic>>? payingRows,
  double? Function(String script, String? category) accountRate, {
  bool Function(String script, String? category)? include,
}) {
  if (payingRows == null || payingRows.isEmpty) return null;
  double? room;
  for (final r in payingRows) {
    final script = (r['script_name'] ?? '').toString().toUpperCase();
    final cat = r['category']?.toString();
    if (include != null && !include(script, cat)) continue;
    final mine = accountRate(script, cat);
    if (mine == null) continue;
    final paying = (r['brk_value'] is num) ? (r['brk_value'] as num).toDouble() : double.tryParse('${r['brk_value']}') ?? 0;
    final m = mine - paying;
    if (room == null || m < room) room = m;
  }
  if (room == null) return null;
  return room < 0 ? 0 : (room * 10000).roundToDouble() / 10000;
}

/// A broker rate box: hint "≤ room", red when above it.
Widget brokerRateBox(TextEditingController controller, double? room, {double height = 36, VoidCallback? onChanged}) {
  final v = NewAccountBrokerDraft.read(controller);
  final over = v != null && room != null && v > room + 1e-9;
  return Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8FF),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: over ? kColorSell : kBrandPrimary.withValues(alpha: 0.35)),
    ),
    child: TextField(
      controller: controller,
      onChanged: (_) => onChanged?.call(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: over ? kColorSell : kColorTextPrimary, fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: room == null ? '0' : '≤${_num(room)}',
        hintStyle: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeCaption, fontWeight: kFontWeightRegular),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: height >= 36 ? 8 : 6),
      ),
    ),
  );
}

/// The "Add broker" card: switch, broker, P&L % and Brokerage %.
class BrokerCreateCard extends StatelessWidget {
  final NewAccountBrokerDraft draft;
  final String accountKind; // 'client' | 'sub-master'
  final String payingName;
  final double pnlMax;
  final double brkMax;
  final String? pnlNote; // e.g. "on top of his own 30%"
  final ValueChanged<bool> onToggle;
  final VoidCallback onChanged;
  const BrokerCreateCard({
    super.key,
    required this.draft,
    required this.accountKind,
    required this.payingName,
    required this.pnlMax,
    required this.brkMax,
    this.pnlNote,
    required this.onToggle,
    required this.onChanged,
  });

  static const _label = TextStyle(color: Color(0xFF475569), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium);

  Widget _pct(String title, TextEditingController c, double max) {
    final v = NewAccountBrokerDraft.read(c);
    final over = v != null && v > max + 1e-9;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$title · max ${_num(max)}', style: _label.copyWith(color: over ? kColorSell : null)),
      const SizedBox(height: 4),
      brokerRateBox(c, max, onChanged: onChanged),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Select broker…')),
      for (final b in draft.brokers.where((b) => b['status'] != 'inactive')) DropdownMenuItem(value: '${b['id']}', child: Text('${b['name']}')),
      const DropdownMenuItem(value: 'new', child: Text('+ New broker…')),
    ];
    final value = items.any((i) => i.value == draft.brokerId) ? draft.brokerId : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
          child: Text('Add broker',
              style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
        ),
        Switch(value: draft.enabled, activeThumbColor: kBrandPrimary, onChanged: onToggle),
      ]),
      if (!draft.enabled)
        Text('Optional — a broker who shares this $accountKind\'s P&L and brokerage. Tracking only.', style: _label.copyWith(color: kColorTextMuted)),
      if (draft.enabled) ...[
        const SizedBox(height: 6),
        if (draft.loadingBrokers)
          const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
        else
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily),
              items: items,
              onChanged: (v) {
                draft.brokerId = v ?? '';
                onChanged();
              },
            ),
          ),
        if (draft.brokerId == 'new') ...[
          const SizedBox(height: 8),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: TextField(
              controller: draft.newName,
              onChanged: (_) => onChanged(),
              style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily),
              decoration: const InputDecoration(border: InputBorder.none, hintText: 'New broker name', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 11)),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _pct('P&L sharing %', draft.pnl, pnlMax)),
          const SizedBox(width: 10),
          Expanded(child: _pct('Brk sharing %', draft.brk, brkMax)),
        ]),
        if (pnlNote != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(pnlNote!, style: _label.copyWith(color: kColorTextMuted))),
        const SizedBox(height: 8),
        Text(
          "The broker's rate goes in the Broker column of Brokerage Settings below (Customize for Index / Stock or per script). "
          "Paid only out of $payingName's own share — the ledger and settlement don't change.",
          style: _label.copyWith(color: kColorTextMuted),
        ),
      ],
    ]);
  }
}

/// Loads the broker list the first time the switch goes on.
Future<void> loadBrokersFor(NewAccountBrokerDraft draft, {required bool isAdmin, required VoidCallback refresh}) async {
  if (draft.brokers.isNotEmpty || draft.loadingBrokers) return;
  draft.loadingBrokers = true;
  refresh();
  try {
    draft.brokers = await BrokerService(isAdmin: isAdmin).list();
  } catch (_) {
    draft.brokers = [];
  } finally {
    draft.loadingBrokers = false;
    refresh();
  }
}

/// Checks before Create. Returns an error text, or null.
String? checkNewAccountBroker(NewAccountBrokerDraft draft, {required double pnlMax, required double brkMax, required List<String> overLimits}) {
  if (!draft.on) return null;
  if (draft.brokerId.isEmpty) return 'Choose a broker, or switch Add broker off.';
  if (draft.brokerId == 'new' && draft.newName.text.trim().isEmpty) return 'Enter the new broker name.';
  final p = NewAccountBrokerDraft.read(draft.pnl);
  final b = NewAccountBrokerDraft.read(draft.brk);
  if (draft.pnl.text.trim().isNotEmpty && (p == null || p < 0)) return 'Enter a valid broker P&L sharing %.';
  if (draft.brk.text.trim().isNotEmpty && (b == null || b < 0)) return 'Enter a valid broker brokerage sharing %.';
  if ((p ?? 0) > pnlMax + 1e-9) return 'Broker P&L sharing can be at most ${_num(pnlMax)}%.';
  if ((b ?? 0) > brkMax + 1e-9) return 'Broker brokerage sharing can be at most ${_num(brkMax)}%.';
  if (overLimits.isNotEmpty) return 'Broker rate above the room: ${overLimits.join(', ')}.';
  return null;
}

/// After the account exists: makes the broker if new, then the link.
/// Returns an error text, or null when done (or nothing to do).
Future<String?> saveNewAccountBroker(
  NewAccountBrokerDraft draft, {
  required bool isAdmin,
  required String kind, // 'client' | 'master'
  required String accountId,
  required List<Map<String, dynamic>> rates,
}) async {
  if (!draft.on) return null;
  final svc = BrokerService(isAdmin: isAdmin);
  try {
    final id = draft.brokerId == 'new' ? '${(await svc.create(name: draft.newName.text.trim()))['id']}' : draft.brokerId;
    final settings = {
      'rates': rates,
      'pnl_share_pct': NewAccountBrokerDraft.read(draft.pnl) ?? 0,
      'brk_share_pct': NewAccountBrokerDraft.read(draft.brk) ?? 0,
    };
    if (kind == 'client') {
      await svc.addClientLink(id, accountId, settings);
    } else {
      await svc.addMasterLink(id, accountId, settings);
    }
    return null;
  } catch (e) {
    return '$e';
  }
}
