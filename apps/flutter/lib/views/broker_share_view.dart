import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/broker_service.dart';
import '../utils/contants.dart';
import '../utils/date_formatter.dart';

/// Broker sharing (owner, 11 Nov 2026) — the app side of the web portal's
/// broker screens. TRACKING ONLY: what is set here never changes the ledger,
/// settlement or any report; the statement READS the Ledger's own weekly
/// figures on the server and shows the broker's part.
///
///   rate per segment     what the broker GETS (client pays 8, field 3 → broker 3)
///   brokerage sharing %  his % of the brokerage left after that
///   P&L sharing %        his % of the Total P&L (profit and loss)
/// The server caps all three so the broker is paid only out of the paying
/// master's own part (shown here as "max …").

final NumberFormat _money = NumberFormat('#,##,##0.00', 'en_IN');
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _fmt(Object? v) => _money.format(_d(v));
String _unit(Object? type) => type == 'LOT WISE' ? '₹/lot' : 'paisa';
String _pct(Object? v) => _d(v) == _d(v).roundToDouble() ? _d(v).toStringAsFixed(0) : _d(v).toString();
Color _tone(double v) => v > 0 ? kColorBuy : (v < 0 ? kColorSell : kColorTextPrimary);

const TextStyle _body = TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium);
const TextStyle _muted = TextStyle(color: kColorTextMuted, fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium);
const TextStyle _label = TextStyle(color: kSectionLabelColor, fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: 0.6);

/* ------------------------------------------------------------------ page frame */

class _BrokerPage extends StatelessWidget {
  final String title;
  final Widget child;
  const _BrokerPage({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: kTopBarTile, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.arrow_back, color: kTopBarFg, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kTopBarFg, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
      width: double.infinity,
      padding: padding,
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(side: const BorderSide(width: 1, color: Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
      ),
      child: child,
    );

Widget _message(String text, {bool ok = false}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: _body.copyWith(color: ok ? const Color(0xFF16A34A) : kColorSell, fontSize: kFontSizeCaption)),
    );

InputDecoration _box(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
    );

Widget _button(String text, VoidCallback? onTap, {bool primary = false}) => SizedBox(
      height: 38,
      child: primary
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(backgroundColor: kBrandPrimary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(text, style: const TextStyle(fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(foregroundColor: kColorTextPrimary, side: const BorderSide(color: Color(0xFFCBD5E1)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(text, style: const TextStyle(fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
            ),
    );

/* ------------------------------------------------------------- settings form */

/// One broker rate as text: "NFO-FUT Index 3 paisa", "MCX-FUT GOLD 150 ₹/lot".
String brokerRateText(Map r) {
  final cat = r['category'];
  final script = r['script'];
  final scope = script != null && '$script'.isNotEmpty
      ? ' $script'
      : (cat == 'INDEX' ? ' Index' : (cat == 'STOCK' ? ' Stock' : ''));
  return '${r['segment']}$scope ${_pct(r['value'])} ${_unit(r['type'])}';
}

/// The three settings for one account, checked against the server's limits.
/// Rates: per segment, plus Index / Stock (NFO) or per script (MCX) when the
/// limits offer them — the most specific one applies to a fill (server).
class BrokerSettingsDraft {
  final TextEditingController pnl = TextEditingController();
  final TextEditingController brk = TextEditingController();
  final Map<String, TextEditingController> rates = {};
  final Map<String, TextEditingController> _category = {}; // 'SEG|INDEX'
  final Map<String, TextEditingController> _script = {}; // 'SEG|GOLD'
  final Set<String> customized = {};

  TextEditingController rate(String segment) => rates.putIfAbsent(segment, () => TextEditingController());
  TextEditingController category(String segment, String cat) => _category.putIfAbsent('$segment|$cat', () => TextEditingController());
  TextEditingController script(String segment, String name) => _script.putIfAbsent('$segment|${name.toUpperCase()}', () => TextEditingController());

  void fillFrom(Map<String, dynamic>? link) {
    pnl.text = _d(link?['pnl_share_pct']) > 0 ? _pct(link?['pnl_share_pct']) : '';
    brk.text = _d(link?['brk_share_pct']) > 0 ? _pct(link?['brk_share_pct']) : '';
    for (final c in [...rates.values, ..._category.values, ..._script.values]) {
      c.text = '';
    }
    customized.clear();
    for (final r in (link?['rates'] as List? ?? const [])) {
      if (r is! Map) continue;
      final seg = '${r['segment']}';
      if (r['script'] != null && '${r['script']}'.isNotEmpty) {
        script(seg, '${r['script']}').text = _pct(r['value']);
        customized.add(seg);
      } else if (r['category'] != null) {
        category(seg, '${r['category']}').text = _pct(r['value']);
        customized.add(seg);
      } else {
        rate(seg).text = _pct(r['value']);
      }
    }
  }

  /// Payload for the server, or throws a readable message.
  Map<String, dynamic> toSettings(Map<String, dynamic> limits) {
    double read(TextEditingController c, String name) {
      final t = c.text.trim();
      if (t.isEmpty) return 0;
      final n = double.tryParse(t);
      if (n == null || n < 0) throw BrokerApiException('Enter a valid number for $name.');
      return n;
    }

    final p = read(pnl, 'P&L sharing');
    final b = read(brk, 'brokerage sharing');
    if (p > _d(limits['pnl_max'])) throw BrokerApiException('P&L sharing can be at most ${_pct(limits['pnl_max'])}%.');
    if (b > _d(limits['brk_max'])) throw BrokerApiException('Brokerage sharing can be at most ${_pct(limits['brk_max'])}%.');
    final out = <Map<String, dynamic>>[];
    void add(double v, double max, String label, Map<String, dynamic> rate, Object? type) {
      if (v == 0) return;
      if (v > max + 1e-9) throw BrokerApiException('$label: the broker can get at most ${_pct(max)} ${_unit(type)}.');
      out.add(rate);
    }

    for (final s in (limits['segments'] as List? ?? const []).whereType<Map>()) {
      final seg = '${s['segment']}';
      final v = read(rate(seg), seg);
      add(v, _d(s['x_max']), seg, {'segment': seg, 'type': s['type'], 'value': v}, s['type']);
      if (!customized.contains(seg)) continue;
      final cats = s['categories'];
      if (cats is Map) {
        for (final cat in const ['INDEX', 'STOCK']) {
          final label = '$seg ${cat == 'INDEX' ? 'Index' : 'Stock'}';
          final cv = read(category(seg, cat), label);
          add(cv, _d((cats[cat] as Map?)?['x_max']), label, {'segment': seg, 'type': s['type'], 'value': cv, 'category': cat}, s['type']);
        }
      }
      for (final sc in (s['scripts'] as List? ?? const []).whereType<Map>()) {
        final name = '${sc['script']}';
        final label = '$seg $name';
        final sv = read(script(seg, name), label);
        add(sv, _d(sc['x_max']), label, {'segment': seg, 'type': s['type'], 'value': sv, 'script': name}, s['type']);
      }
    }
    return {'rates': out, 'pnl_share_pct': p, 'brk_share_pct': b};
  }

  void dispose() {
    pnl.dispose();
    brk.dispose();
    for (final c in [...rates.values, ..._category.values, ..._script.values]) {
      c.dispose();
    }
  }
}

class _SettingsFields extends StatefulWidget {
  final Map<String, dynamic> limits;
  final BrokerSettingsDraft draft;
  const _SettingsFields({required this.limits, required this.draft});

  @override
  State<_SettingsFields> createState() => _SettingsFieldsState();
}

class _SettingsFieldsState extends State<_SettingsFields> {
  Widget _row(String title, String hint, TextEditingController c, {double indent = 0, double width = 90}) => Padding(
        padding: EdgeInsets.only(top: 6, bottom: 6, left: indent),
        child: Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: _body),
                const SizedBox(height: 2),
                Text(hint, style: _muted),
              ]),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: width,
              child: TextField(
                controller: c,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _box('0'),
                style: _body,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final limits = widget.limits;
    final draft = widget.draft;
    final isSub = limits['kind'] == 'master';
    final target = limits['target'] is Map ? limits['target'] as Map : const {};
    final paying = limits['paying_master'] is Map ? limits['paying_master'] as Map : const {};
    final subName = '${target['name'] ?? target['username'] ?? ''}';
    final payName = '${paying['name'] ?? paying['username'] ?? 'the master'}';
    final segs = (limits['segments'] as List? ?? const []).whereType<Map>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('P&L sharing %',
            '${isSub ? "His own %, on top of $subName's ${_pct(limits['below_pnl_pct'])}%" : 'Profit and loss both'} · max ${_pct(limits['pnl_max'])}%', draft.pnl),
        _row('Brokerage sharing %',
            '${isSub ? "His own %, on top of $subName's ${_pct(limits['below_brk_pct'])}%" : 'Of the brokerage left after his rate'} · max ${_pct(limits['brk_max'])}%', draft.brk),
        if (segs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(isSub ? "BROKER'S RATE PER SEGMENT (GAP BETWEEN $subName's RATE AND HIS PARENT'S)".toUpperCase() : 'BROKER GETS PER SEGMENT (OUT OF THE BROKERAGE CHARGED)', style: _label),
          for (final s in segs) ..._segment(s),
        ],
        const SizedBox(height: 6),
        Text("Comes only out of $payName's own share. Tracking only — the ledger and settlement stay exactly as they are. All 0 = the broker only sees the account.", style: _muted),
      ],
    );
  }

  /// One segment: its rate, and — when it has an Index / Stock split or
  /// scripts — a Customize switch opening those rows.
  List<Widget> _segment(Map s) {
    final draft = widget.draft;
    final seg = '${s['segment']}';
    final cats = s['categories'] is Map ? s['categories'] as Map : null;
    final scripts = (s['scripts'] as List? ?? const []).whereType<Map>().toList();
    final canCustomize = cats != null || scripts.isNotEmpty;
    final open = draft.customized.contains(seg);
    return [
      Row(children: [
        Expanded(child: _row(seg, '${_unit(s['type'])} · max ${_pct(s['x_max'])}${canCustomize ? ' · all others' : ''}', draft.rate(seg))),
        if (canCustomize)
          IconButton(
            tooltip: open ? 'Close' : 'Customize',
            icon: Icon(open ? Icons.expand_less : Icons.tune, size: 20, color: open ? kBrandPrimary : kColorTextMuted),
            onPressed: () => setState(() => open ? draft.customized.remove(seg) : draft.customized.add(seg)),
          ),
      ]),
      if (open && cats != null)
        for (final cat in const ['INDEX', 'STOCK'])
          _row(cat == 'INDEX' ? 'Index' : 'Stock', 'max ${_pct((cats[cat] as Map?)?['x_max'])}', draft.category(seg, cat), indent: 14, width: 80),
      if (open)
        for (final sc in scripts)
          _row('${sc['script']}', 'client ${_pct(sc['below'])} · master ${_pct(sc['paying'])} · max ${_pct(sc['x_max'])}', draft.script(seg, '${sc['script']}'), indent: 14, width: 80),
    ];
  }
}

/* ------------------------------------------------------- one account's broker */

/// The "Broker" screen of a client or sub-master: his current broker and share; change or remove.
class AccountBrokerView extends StatefulWidget {
  /// 'client' or 'master' (a sub-master: the broker gets a share of his whole tree).
  final String kind;
  final String id;
  final String name;
  final bool isAdmin;
  const AccountBrokerView({super.key, required this.kind, required this.id, required this.name, required this.isAdmin});

  @override
  State<AccountBrokerView> createState() => _AccountBrokerViewState();
}

class _AccountBrokerViewState extends State<AccountBrokerView> {
  late final BrokerService _svc = BrokerService(isAdmin: widget.isAdmin);
  final BrokerSettingsDraft _draft = BrokerSettingsDraft();
  final TextEditingController _newName = TextEditingController();
  List<Map<String, dynamic>> _brokers = [];
  Map<String, dynamic>? _limits;
  bool _loading = true;
  bool _busy = false;
  bool _editing = false;
  String? _error;
  String? _msg;
  bool _msgOk = false;
  String _brokerId = '';

  bool get _isClient => widget.kind == 'client';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    _newName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _svc.list(),
        _svc.limits(userId: _isClient ? widget.id : null, masterId: _isClient ? null : widget.id),
      ]);
      if (!mounted) return;
      setState(() {
        _brokers = results[0] as List<Map<String, dynamic>>;
        _limits = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  /// The open link on this account, with its broker.
  ({Map<String, dynamic> broker, Map<String, dynamic> link})? get _current {
    for (final b in _brokers) {
      final links = (_isClient ? b['links'] : b['master_links']) as List? ?? const [];
      for (final l in links.whereType<Map>()) {
        final who = (_isClient ? l['client'] : l['sub_master']);
        if (who is Map && '${who['id']}' == widget.id && l['to'] == null) {
          return (broker: b, link: Map<String, dynamic>.from(l));
        }
      }
    }
    return null;
  }

  void _startEdit() {
    final cur = _current;
    _brokerId = cur == null ? '' : '${cur.broker['id']}';
    _draft.fillFrom(cur?.link);
    setState(() {
      _editing = true;
      _msg = null;
    });
  }

  Future<void> _save() async {
    final limits = _limits;
    if (limits == null) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      if (_brokerId.isEmpty) throw BrokerApiException('Choose a broker.');
      if (_brokerId == 'new' && _newName.text.trim().isEmpty) throw BrokerApiException('Enter the new broker name.');
      final settings = _draft.toSettings(limits);
      final id = _brokerId == 'new' ? '${(await _svc.create(name: _newName.text.trim()))['id']}' : _brokerId;
      if (_isClient) {
        await _svc.addClientLink(id, widget.id, settings);
      } else {
        await _svc.addMasterLink(id, widget.id, settings);
      }
      _newName.clear();
      _editing = false;
      _msg = 'Saved. It applies from this week (the whole week).';
      _msgOk = true;
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = '$e';
          _msgOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final cur = _current;
    if (cur == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove broker?'),
        content: Text('Remove ${cur.broker['name']} from ${widget.name}? Past weeks keep their share.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      if (_isClient) {
        await _svc.endClientLink('${cur.link['id']}');
      } else {
        await _svc.endMasterLink('${cur.link['id']}');
      }
      _msg = 'Broker removed.';
      _msgOk = true;
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = '$e';
          _msgOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _settingsText(Map<String, dynamic> link) {
    final rates = (link['rates'] as List? ?? const []).whereType<Map>().map(brokerRateText).join(' · ');
    return 'P&L ${_pct(link['pnl_share_pct'])}% · Brokerage sharing ${_pct(link['brk_share_pct'])}% · ${rates.isEmpty ? 'no per-segment rate' : rates}';
  }

  @override
  Widget build(BuildContext context) {
    return _BrokerPage(
      title: '${widget.name} - Broker',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: kBrandPrimary))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: _body, textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    _card(child: _editing ? _editor() : _summary()),
                    if (_msg != null) _message(_msg!, ok: _msgOk),
                  ],
                ),
    );
  }

  Widget _summary() {
    final cur = _current;
    if (cur == null) {
      return Row(children: [
        Expanded(child: Text('No broker on this ${_isClient ? 'client' : 'sub-master'}.', style: _body)),
        _button('Add broker', _busy ? null : _startEdit, primary: true),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Broker: ${cur.broker['name']}', style: _body.copyWith(fontWeight: kFontWeightSemiBold)),
      const SizedBox(height: 2),
      Text('since ${DateFormatter.formatDateTime('${cur.link['from']}')}', style: _muted),
      const SizedBox(height: 8),
      Text(_settingsText(cur.link), style: _body),
      const SizedBox(height: 12),
      Row(children: [
        _button('Change', _busy ? null : _startEdit),
        const SizedBox(width: 10),
        _button('Remove', _busy ? null : _remove),
      ]),
    ]);
  }

  Widget _editor() {
    final active = _brokers.where((b) => b['status'] != 'inactive').toList();
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Select…')),
      for (final b in active) DropdownMenuItem(value: '${b['id']}', child: Text('${b['name']}')),
      const DropdownMenuItem(value: 'new', child: Text('+ New broker…')),
    ];
    final value = items.any((i) => i.value == _brokerId) ? _brokerId : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('BROKER', style: _label),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          style: _body,
          items: items,
          onChanged: (v) => setState(() => _brokerId = v ?? ''),
        ),
      ),
      if (_brokerId == 'new') ...[
        const SizedBox(height: 8),
        TextField(controller: _newName, decoration: _box('New broker name'), style: _body),
      ],
      const SizedBox(height: 10),
      if (_limits != null) _SettingsFields(limits: _limits!, draft: _draft),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        _button('Cancel', _busy ? null : () => setState(() => _editing = false)),
        const SizedBox(width: 10),
        _button(_busy ? 'Saving…' : 'Save', _busy ? null : _save, primary: true),
      ]),
    ]);
  }
}

/* --------------------------------------------------------- "Brokers allowed" */

/// Admin → a master: lets him add brokers to his own clients and sub-masters.
class BrokersAllowedView extends StatefulWidget {
  final String masterId;
  final String masterName;
  const BrokersAllowedView({super.key, required this.masterId, required this.masterName});

  @override
  State<BrokersAllowedView> createState() => _BrokersAllowedViewState();
}

class _BrokersAllowedViewState extends State<BrokersAllowedView> {
  final BrokerService _svc = BrokerService(isAdmin: true);
  bool? _allowed;
  bool _busy = false;
  String? _msg;
  bool _msgOk = false;

  @override
  void initState() {
    super.initState();
    _svc.masterAllowed(widget.masterId).then((v) {
      if (mounted) setState(() => _allowed = v);
    }).catchError((Object e) {
      if (mounted) setState(() => _msg = '$e');
    });
  }

  Future<void> _set(bool v) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await _svc.setMasterAllowed(widget.masterId, v);
      setState(() {
        _allowed = v;
        _msg = v ? '${widget.masterName} can now use brokers.' : 'Brokers switched off for ${widget.masterName}.';
        _msgOk = true;
      });
    } catch (e) {
      setState(() {
        _msg = '$e';
        _msgOk = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BrokerPage(
      title: '${widget.masterName} - Brokers Allowed',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _card(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_allowed == null ? 'Loading…' : (_allowed! ? 'On — Brokers is in his menu' : 'Off — no broker option for him'), style: _body),
                  const SizedBox(height: 4),
                  const Text("His brokers are paid only out of his own share. Tracking only — the ledger and settlement don't change.", style: _muted),
                ]),
              ),
              Switch(value: _allowed ?? false, activeThumbColor: kBrandPrimary, onChanged: (_allowed == null || _busy) ? null : _set),
            ]),
          ),
          if (_msg != null) _message(_msg!, ok: _msgOk),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------- brokers list */

/// Menu → Brokers. Admin: every broker. Master: his own brokers (only when allowed).
class BrokersView extends StatefulWidget {
  final bool isAdmin;
  const BrokersView({super.key, required this.isAdmin});

  @override
  State<BrokersView> createState() => _BrokersViewState();
}

class _BrokersViewState extends State<BrokersView> {
  late final BrokerService _svc = BrokerService(isAdmin: widget.isAdmin);
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  List<Map<String, dynamic>> _brokers = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _msg;
  bool _msgOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await _svc.list();
      if (mounted) {
        setState(() {
          _brokers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final b = await _svc.create(name: _name.text.trim(), phone: _phone.text.trim());
      _name.clear();
      _phone.clear();
      _msg = 'Broker ${b['name']} created. To add him to a client or sub-master, open that account → Broker.';
      _msgOk = true;
      await _load();
    } catch (e) {
      setState(() {
        _msg = '$e';
        _msgOk = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static int _openCount(Map<String, dynamic> b) =>
      [...(b['links'] as List? ?? const []), ...(b['master_links'] as List? ?? const [])].whereType<Map>().where((l) => l['to'] == null).length;

  @override
  Widget build(BuildContext context) {
    return _BrokerPage(
      title: 'Brokers',
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: kBrandPrimary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  _card(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('NEW BROKER', style: _label),
                      const SizedBox(height: 8),
                      TextField(controller: _name, decoration: _box('Name'), style: _body),
                      const SizedBox(height: 8),
                      TextField(controller: _phone, decoration: _box('Phone (optional)'), style: _body, keyboardType: TextInputType.phone),
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: _button(_busy ? 'Creating…' : '+ Create', _busy ? null : _create, primary: true)),
                      if (_msg != null) _message(_msg!, ok: _msgOk),
                      const SizedBox(height: 6),
                      Text(
                          widget.isAdmin
                              ? 'Tracking only — nothing here changes the ledger or settlement.'
                              : 'Your brokers — their share comes only out of your own share. Tracking only.',
                          style: _muted),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) Text(_error!, style: _body.copyWith(color: kColorSell)),
                  if (_error == null && _brokers.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No brokers yet.', style: _muted))),
                  for (final b in _brokers) ...[
                    _card(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        title: Text('${b['name']}', style: _body.copyWith(fontWeight: kFontWeightSemiBold)),
                        subtitle: Text(
                          '${_openCount(b)} account(s) linked'
                          '${(b['login'] is Map && b['login']['enabled'] == true) ? ' · login on' : ''}'
                          '${b['status'] == 'inactive' ? ' · inactive' : ''}'
                          '${widget.isAdmin && b['owner_master'] is Map ? ' · ${b['owner_master']['name']}\'s' : ''}',
                          style: _muted,
                        ),
                        trailing: const Icon(Icons.chevron_right, color: kColorTextMuted),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => BrokerDetailView(broker: b, isAdmin: widget.isAdmin)));
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
    );
  }
}

/* ------------------------------------------------------------ one broker */

class BrokerDetailView extends StatefulWidget {
  final Map<String, dynamic> broker;
  final bool isAdmin;
  const BrokerDetailView({super.key, required this.broker, required this.isAdmin});

  @override
  State<BrokerDetailView> createState() => _BrokerDetailViewState();
}

class _BrokerDetailViewState extends State<BrokerDetailView> {
  late final BrokerService _svc = BrokerService(isAdmin: widget.isAdmin);
  late Map<String, dynamic> _broker = widget.broker;
  late final TextEditingController _user = TextEditingController(text: _login['username']?.toString() ?? '');
  final TextEditingController _pass = TextEditingController();
  bool _busy = false;
  String? _msg;
  bool _msgOk = false;

  Map get _login => _broker['login'] is Map ? _broker['login'] as Map : const {};
  String get _id => '${_broker['id']}';

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await _svc.list();
    final me = list.where((b) => '${b['id']}' == _id);
    if (mounted && me.isNotEmpty) setState(() => _broker = me.first);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await action();
      _pass.clear();
      _msg = done;
      _msgOk = true;
      await _reload();
    } catch (e) {
      _msg = '$e';
      _msgOk = false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveLogin() {
    final u = _user.text.trim();
    final changedUser = u != (_login['username']?.toString() ?? '');
    final p = _pass.text;
    if (!changedUser && p.isEmpty) {
      setState(() {
        _msg = 'Nothing changed.';
        _msgOk = false;
      });
      return;
    }
    _run(() => _svc.setLogin(_id, username: changedUser ? u : null, password: p.isEmpty ? null : p),
        p.isNotEmpty ? 'Saved. His open sessions were signed out.' : 'Saved.');
  }

  Future<void> _endLink(Map link, bool sub) async {
    final who = sub ? link['sub_master'] : link['client'];
    final name = who is Map ? '${who['name']}' : 'this account';
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove broker?'),
        content: Text('Remove ${_broker['name']} from $name? Past weeks keep their share.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() => sub ? _svc.endMasterLink('${link['id']}') : _svc.endClientLink('${link['id']}'), 'Removed from $name.');
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _login['enabled'] == true;
    final links = [
      for (final l in (_broker['links'] as List? ?? const []).whereType<Map>().where((l) => l['to'] == null)) (link: l, sub: false),
      for (final l in (_broker['master_links'] as List? ?? const []).whereType<Map>().where((l) => l['to'] == null)) (link: l, sub: true),
    ];
    return _BrokerPage(
      title: '${_broker['name']}',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('BROKER LOGIN ', style: _label),
                Text(enabled ? 'ON' : 'OFF', style: _label.copyWith(color: enabled ? const Color(0xFF16A34A) : kColorTextMuted)),
              ]),
              const SizedBox(height: 4),
              const Text('He signs in on the web portal login page; view only.', style: _muted),
              const SizedBox(height: 10),
              TextField(controller: _user, decoration: _box('Username'), style: _body, autocorrect: false),
              const SizedBox(height: 8),
              TextField(controller: _pass, decoration: _box(_login['username'] != null ? 'New password' : 'Password (6+)'), style: _body, obscureText: true),
              const SizedBox(height: 10),
              Row(children: [
                _button('Save', _busy ? null : _saveLogin),
                const SizedBox(width: 10),
                _button(enabled ? 'Turn login off' : 'Turn login on',
                    _busy ? null : () => _run(() => _svc.setLogin(_id, enabled: !enabled), enabled ? 'Login off — he was signed out.' : 'Login on.')),
              ]),
              if (_msg != null) _message(_msg!, ok: _msgOk),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('LINKED ACCOUNTS', style: _label),
          const SizedBox(height: 8),
          _card(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: links.isEmpty
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('None — open a client or sub-master → Broker to add him.', style: _muted))
                : Column(children: [
                    for (var i = 0; i < links.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _linkRow(links[i].link, links[i].sub),
                    ],
                  ]),
          ),
          const SizedBox(height: 16),
          Text(widget.isAdmin ? "STATEMENT — ${_broker['name']}'S SHARE".toUpperCase() : 'STATEMENT — WHAT YOU OWE ${_broker['name']}'.toUpperCase(), style: _label),
          const SizedBox(height: 8),
          BrokerStatementPanel(loader: () => _svc.statement(_id, weeks: 12), showPayingMaster: widget.isAdmin),
        ],
      ),
    );
  }

  Widget _linkRow(Map link, bool sub) {
    final who = (sub ? link['sub_master'] : link['client']) as Map? ?? const {};
    final rates = (link['rates'] as List? ?? const []).whereType<Map>().map(brokerRateText).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${who['name'] ?? '?'}  ${who['username'] ?? ''}', style: _body.copyWith(fontWeight: kFontWeightSemiBold)),
            const SizedBox(height: 2),
            Text('${sub ? 'sub-master' : 'client'} · since ${DateFormatter.formatDate('${link['from']}')}', style: _muted),
            const SizedBox(height: 2),
            Text('P&L ${_pct(link['pnl_share_pct'])}% · Brk ${_pct(link['brk_share_pct'])}%${rates.isEmpty ? '' : ' · $rates'}', style: _muted.copyWith(color: kColorTextPrimary)),
          ]),
        ),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.link_off, color: kColorSell, size: 20),
          onPressed: _busy ? null : () => _endLink(link, sub),
        ),
      ]),
    );
  }
}

/* ---------------------------------------------------------------- statement */

/// Week picker + the Ledger-style table. `loader` fetches the statement.
class BrokerStatementPanel extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() loader;
  final bool showPayingMaster;
  const BrokerStatementPanel({super.key, required this.loader, this.showPayingMaster = false});

  @override
  State<BrokerStatementPanel> createState() => _BrokerStatementPanelState();
}

class _BrokerStatementPanelState extends State<BrokerStatementPanel> {
  List<Map<String, dynamic>> _weeks = [];
  int _pick = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.loader().then((s) {
      if (!mounted) return;
      setState(() {
        _weeks = (s['weeks'] as List? ?? const []).whereType<Map>().map((w) => Map<String, dynamic>.from(w)).toList();
        _loading = false;
      });
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: kBrandPrimary)));
    if (_error != null) return Text(_error!, style: _body.copyWith(color: kColorSell));
    if (_weeks.isEmpty) return const Text('No broker share yet.', style: _muted);
    final week = _weeks[_pick.clamp(0, _weeks.length - 1)];
    final totals = week['totals'] is Map ? week['totals'] as Map : const {};
    final net = _d(totals['net']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
            child: DropdownButton<int>(
              value: _pick.clamp(0, _weeks.length - 1),
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: _body,
              items: [for (var i = 0; i < _weeks.length; i++) DropdownMenuItem(value: i, child: Text('${_weeks[i]['label']}'))],
              onChanged: (v) => setState(() => _pick = v ?? 0),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        if (week['current'] == true) Text('Live — final after the weekly settlement', style: _muted.copyWith(color: const Color(0xFFD97706))),
        const Spacer(),
        const Text('Net to broker: ', style: _body),
        Text(_fmt(net), style: _body.copyWith(color: _tone(net), fontWeight: kFontWeightBold)),
      ]),
      const SizedBox(height: 8),
      BrokerStatementTable(week: week, showPayingMaster: widget.showPayingMaster),
      const SizedBox(height: 8),
      const Text(
        "Total P&L and Brokerage = the Ledger's own figures (a client's loss shows as +). Net MTM = Self + Downline + Upline. "
        "Self = the broker's share; Downline = the sub-master and his tree; Upline = the paying master and above. "
        'Tracking only — settled with the broker outside the system.',
        style: _muted,
      ),
    ]);
  }
}

class _Line {
  final String type; // C or M
  final String name;
  final String code;
  final String? under;
  final String? paying;
  final Map pnl;
  final Map brk;
  final double net;
  _Line(this.type, this.name, this.code, this.under, this.paying, this.pnl, this.brk, this.net);
}

/// One row per account like the Ledger (a broker on a sub-master: every
/// account under him), then the Total. Name pinned on the left; the figures
/// scroll sideways.
class BrokerStatementTable extends StatelessWidget {
  final Map<String, dynamic> week;
  final bool showPayingMaster;
  const BrokerStatementTable({super.key, required this.week, this.showPayingMaster = false});

  static const double _rowH = 46;
  static const double _headH = 34;
  static const double _numW = 96;
  static const Color _line = Color(0xFF94A3B8);
  static const Color _headBg = Color(0xFFE0E7FF);
  static const Color _bodyBg = Color(0xFFF5F7FF);
  static const Color _footBg = Color(0xFFE8EDFF);

  static const List<(String, bool)> _heads = [
    ('Total P&L', false),
    ('Brokerage', false),
    ('Net MTM', false),
    ('Self P&L', true),
    ('Self Brk', true),
    ('Self MTM', true),
    ('Downline MTM', false),
    ('Upline MTM', false),
  ];

  List<_Line> _lines() {
    final out = <_Line>[];
    for (final r in (week['rows'] as List? ?? const []).whereType<Map>()) {
      final t = r['target'] is Map ? r['target'] as Map : const {};
      final paying = r['paying_master'] is Map ? '${r['paying_master']['name']}' : null;
      final parts = t['type'] == 'master' && r['accounts'] is List && (r['accounts'] as List).isNotEmpty ? (r['accounts'] as List).whereType<Map>() : null;
      if (parts != null) {
        for (final a in parts) {
          final at = a['target'] is Map ? a['target'] as Map : const {};
          out.add(_Line(at['type'] == 'client' ? 'C' : 'M', '${at['name']}', '${at['username']}', '${t['name']}', paying, a['pnl'] as Map? ?? const {}, a['brokerage'] as Map? ?? const {}, _d(a['net'])));
        }
      } else {
        out.add(_Line(t['type'] == 'client' ? 'C' : 'M', '${t['name']}', '${t['username']}', null, paying, r['pnl'] as Map? ?? const {}, r['brokerage'] as Map? ?? const {}, _d(r['net'])));
      }
    }
    return out;
  }

  static List<double> _mtm(Map pnl, Map brk, double net) => [
        _d(pnl['total']),
        _d(brk['total']),
        _d(pnl['total']) + _d(brk['total']),
        _d(pnl['self']),
        _d(brk['self']),
        net,
        _d(pnl['below']) + _d(brk['below']),
        _d(pnl['upline']) + _d(brk['upline']),
      ];

  Widget _cell(String text, {required double w, required double h, required Color bg, bool head = false, bool right = true, Color? color, bool bold = false, bool last = false}) =>
      Container(
        width: w,
        height: h,
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: bg, border: Border(right: last ? BorderSide.none : const BorderSide(color: _line, width: 0.6), bottom: const BorderSide(color: _line, width: 0.6))),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color ?? (head ? const Color(0xFF111827) : kColorTextPrimary),
            fontSize: head ? kFontSizeSubtitle : kFontSizeCaption,
            fontFamily: kFontFamily,
            fontWeight: head || bold ? kFontWeightSemiBold : kFontWeightMedium,
            letterSpacing: head ? 0.4 : 0,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lines = _lines();
    if (lines.isEmpty) return const Text('No linked account this week.', style: _muted);
    final showUnder = lines.any((l) => l.under != null);
    final totals = week['totals'] is Map ? week['totals'] as Map : const {};
    final totalVals = _mtm(totals['pnl'] as Map? ?? const {}, totals['brokerage'] as Map? ?? const {}, _d(totals['net']));

    // Pinned left part: # | Type | Name (code below).
    const double wNo = 26, wType = 34, wName = 112;
    Widget nameCell(_Line l) => Container(
          width: wName,
          height: _rowH,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: const BoxDecoration(color: _bodyBg, border: Border(right: BorderSide(color: _line, width: 1.2), bottom: BorderSide(color: _line, width: 0.6))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _body.copyWith(fontSize: kFontSizeCaption, fontWeight: kFontWeightSemiBold)),
            Text(l.code, maxLines: 1, overflow: TextOverflow.ellipsis, style: _muted.copyWith(fontSize: kFontSizeSubtitle)),
          ]),
        );

    final left = Column(children: [
      Row(children: [
        _cell('#', w: wNo, h: _headH, bg: _headBg, head: true, right: false),
        _cell('TYPE', w: wType, h: _headH, bg: _headBg, head: true, right: false),
        Container(
          width: wName,
          height: _headH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: const BoxDecoration(color: _headBg, border: Border(right: BorderSide(color: _line, width: 1.2), bottom: BorderSide(color: _line, width: 0.6))),
          child: const Text('NAME / CODE', style: TextStyle(color: Color(0xFF111827), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: 0.4)),
        ),
      ]),
      for (var i = 0; i < lines.length; i++)
        Row(children: [
          _cell('${i + 1}', w: wNo, h: _rowH, bg: _bodyBg, right: false, color: kColorTextMuted),
          _cell(lines[i].type, w: wType, h: _rowH, bg: _bodyBg, right: false, color: kColorTextMuted),
          nameCell(lines[i]),
        ]),
      Row(children: [
        _cell('', w: wNo, h: _rowH, bg: _footBg),
        _cell('', w: wType, h: _rowH, bg: _footBg),
        Container(
          width: wName,
          height: _rowH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: const BoxDecoration(color: _footBg, border: Border(right: BorderSide(color: _line, width: 1.2))),
          child: Text('Total (${lines.length})', style: _body.copyWith(fontSize: kFontSizeCaption, fontWeight: kFontWeightBold)),
        ),
      ]),
    ]);

    // Scrolling right part: [Under] [Paid from] + the 8 figures.
    final extra = <(String, double)>[if (showUnder) ('UNDER', 80), if (showPayingMaster) ('PAID FROM', 90)];
    final right = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final e in extra) _cell(e.$1, w: e.$2, h: _headH, bg: _headBg, head: true, right: false),
        for (var k = 0; k < _heads.length; k++)
          _cell(_heads[k].$1.toUpperCase(), w: _numW, h: _headH, bg: _headBg, head: true, color: _heads[k].$2 ? kBrandPrimary : null, last: k == _heads.length - 1),
      ]),
      for (final l in lines)
        Row(children: [
          if (showUnder) _cell(l.under ?? '—', w: 80, h: _rowH, bg: _bodyBg, right: false, color: kColorTextMuted),
          if (showPayingMaster) _cell(l.paying ?? '—', w: 90, h: _rowH, bg: _bodyBg, right: false, color: kColorTextMuted),
          for (final (k, v) in _mtm(l.pnl, l.brk, l.net).indexed)
            _cell(_fmt(v), w: _numW, h: _rowH, bg: _bodyBg, color: _heads[k].$2 ? _tone(v) : null, bold: _heads[k].$2, last: k == _heads.length - 1),
        ]),
      Row(children: [
        for (final e in extra) _cell('', w: e.$2, h: _rowH, bg: _footBg),
        for (final (k, v) in totalVals.indexed)
          _cell(_fmt(v), w: _numW, h: _rowH, bg: _footBg, color: _heads[k].$2 ? _tone(v) : null, bold: true, last: k == _heads.length - 1),
      ]),
    ]);

    return Container(
      decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        left,
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: right)),
      ]),
    );
  }
}
