import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';
import '../utils/settlement_view.dart';

/// Settlement Report — the reference terminal's layout: one account's view of
/// the period, as PROFIT / LOSS sections of each direct child (what it hands
/// over after its own share), My Brokerage / My Profit/Loss (what this
/// account keeps) and Admin (what it passes up), with "Total Profit & Loss" =
/// My Brokerage + My Profit/Loss. Tapping a child row opens that child's own
/// view (Back returns).
///
/// Every figure comes from GET /master/weekly-admin-report — the same sharing
/// engine as the ledger — regrouped by utils/settlement_view.dart; nothing is
/// computed here. A master's view is that report "as" the master
/// (as_master_id); a client's view is its row in its master's report.
/// "With Opening: Yes" widens the period to start from the first trade.
class SettlementReportView extends StatefulWidget {
  final Master? master;
  final User? user;

  const SettlementReportView({super.key, this.master, this.user});

  @override
  State<SettlementReportView> createState() => _SettlementReportViewState();
}

class _SettlementReportViewState extends State<SettlementReportView> {
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;

  // Date range
  String _selectedRange = 'this_week';
  final _rangeOptions = ['this_week', 'previous_week', 'custom'];
  final _rangeLabels = {
    'this_week': 'This Week',
    'previous_week': 'Previous Week',
    'custom': 'Custom period',
  };
  DateTime? _customFrom;
  DateTime? _customTo;

  // Accounts for the dropdown: {id, name, username, type: 'User'|'Master', pnl_sharing, master_id}
  List<Map<String, dynamic>> _entities = [];

  // Drill-down path — the last entry is the account being viewed:
  // {kind: 'self'|'master'|'user', id, name, username, master_id (user only)}
  List<Map<String, dynamic>> _path = [
    {'kind': 'self'}
  ];
  Map<String, dynamic> get _scope => _path.last;

  // With Opening
  bool _withOpening = false;

  bool _profitExpanded = true;
  bool _lossExpanded = true;

  /// GET /master/weekly-admin-report body for the current scope.
  Map<String, dynamic>? _report;

  /// "With Opening" reaches back to the first trade.
  static const _openingFrom = '2000-01-01';

  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    // Opened from an account's page: start on that account's view.
    if (widget.user != null) {
      _path = [
        {'kind': 'self'},
        {
          'kind': 'user',
          'id': widget.user!.id,
          'name': widget.user!.name,
          'username': widget.user!.username,
          'master_id': widget.user!.masterId,
        },
      ];
    } else if (widget.master != null) {
      _path = [
        {'kind': 'self'},
        {'kind': 'master', 'id': widget.master!.id, 'name': widget.master!.name, 'username': widget.master!.username},
      ];
    }
    _fetchEntities();
    _fetchReport();
  }

  // ── Date range helpers — same Monday-start convention the backend uses ──

  DateTime _mondayOf(DateTime d) {
    final diff = d.weekday - DateTime.monday; // Monday = 1
    final monday = d.subtract(Duration(days: diff));
    return DateTime(monday.year, monday.month, monday.day);
  }

  (DateTime, DateTime) _resolveRange() {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 'previous_week':
        final thisMonday = _mondayOf(now);
        final prevMonday = thisMonday.subtract(const Duration(days: 7));
        final prevSaturday = thisMonday.subtract(const Duration(days: 2));
        return (prevMonday, prevSaturday);
      case 'custom':
        final from = _customFrom ?? _mondayOf(now);
        final to = _customTo ?? now;
        return (from, DateTime(to.year, to.month, to.day, 23, 59, 59));
      case 'this_week':
      default:
        return (_mondayOf(now), now);
    }
  }

  String _fmtIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Fetching ──

  Future<void> _fetchEntities() async {
    try {
      final token = await _storage.getToken();
      final profile = context.read<UserProfileProvider>();
      final isAdmin = profile.isAdmin;
      final usersEndpoint = isAdmin ? '/admin/users?limit=500' : '/master/users?limit=500';
      final mastersEndpoint = isAdmin ? '/masters?limit=500' : '/master/masters?limit=500';
      final api = ApiService(backendUrl);

      final results = await Future.wait([
        api.get(usersEndpoint, token: token),
        api.get(mastersEndpoint, token: token),
      ]);

      final merged = <Map<String, dynamic>>[];
      if (results[0].statusCode == 200) {
        final body = jsonDecode(results[0].body);
        final nested = body['data'];
        final List list = nested is Map ? (nested['users'] ?? []) : (nested ?? []);
        for (final u in list) {
          final mid = u['master_id'];
          merged.add({
            'id': u['id'] ?? u['_id'],
            'name': u['name'],
            'username': u['username'],
            'type': 'User',
            'pnl_sharing': (u['pnl_sharing'] as num?)?.toDouble() ?? 0.0,
            'master_id': mid is Map ? (mid['id'] ?? mid['_id'])?.toString() : mid?.toString(),
          });
        }
      }
      if (results[1].statusCode == 200) {
        final body = jsonDecode(results[1].body);
        final nested = body['data'];
        final List list = nested is Map ? (nested['masters'] ?? []) : (nested ?? []);
        for (final m in list) {
          merged.add({
            'id': m['id'] ?? m['_id'],
            'name': m['name'],
            'username': m['username'],
            'type': 'Master',
            'pnl_sharing': (m['pnl_sharing'] as num?)?.toDouble() ?? 0.0,
          });
        }
      }
      if (mounted) setState(() => _entities = merged);
    } catch (_) {
      // Non-fatal — the dropdown just stays empty/pre-selected; the report itself can still load.
    }
  }

  /// as_master_id for the current scope: a master's own report, or a client's master's report.
  String? get _asMasterId {
    final s = _scope;
    if (s['kind'] == 'master') return '${s['id']}';
    if (s['kind'] == 'user') {
      final m = s['master_id']?.toString();
      return (m == null || m.isEmpty) ? null : m;
    }
    return null;
  }

  Future<void> _fetchReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final (from, to) = _resolveRange();
      final token = await _storage.getToken();
      // Same date handling as the web report: the backend applies date_to as
      // midnight UTC with $lte, so a past To day is sent as the next day; a
      // range ending today sends none.
      final today = _fmtIso(DateTime.now());
      final toIso = _fmtIso(to);
      final params = <String>[
        'date_from=${_withOpening ? _openingFrom : _fmtIso(from)}',
        if (toIso.compareTo(today) < 0) 'date_to=${_fmtIso(DateTime(to.year, to.month, to.day).add(const Duration(days: 1)))}',
        if (_asMasterId != null) 'as_master_id=$_asMasterId',
      ];
      final res = await ApiService(backendUrl).get('/master/weekly-admin-report?${params.join('&')}', token: token);
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        setState(() {
          _report = Map<String, dynamic>.from(body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = body['message'] ?? 'Failed to load report';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  /// The rows on screen, regrouped from the report (utils/settlement_view.dart).
  SettlementView get _view {
    final report = _report;
    if (report == null) return SettlementView.empty;
    if (_scope['kind'] == 'user') {
      final rows = List.from(report['data'] ?? []);
      final row = rows.cast<Map>().where((r) => '${r['id']}' == '${_scope['id']}').firstOrNull;
      return buildClientSettlementView(row == null ? null : Map<String, dynamic>.from(row));
    }
    final sharing = <String, double>{
      for (final e in _entities) '${e['id']}': (e['pnl_sharing'] as double?) ?? 0.0,
    };
    return buildMasterSettlementView(report, sharing);
  }

  String get _viewerName {
    final s = _scope;
    if (s['kind'] != 'self') return '${s['username'] ?? ''}';
    final profile = context.read<UserProfileProvider>();
    return profile.master?.username ?? profile.user?.username ?? 'My account';
  }

  void _drill(SettlementLine l) {
    final d = l.drill;
    if (d == null) return;
    final Map<String, dynamic> next;
    if (d['type'] == 'master') {
      next = {'kind': 'master', 'id': d['id'], 'name': d['name'], 'username': d['username']};
    } else {
      // A client's figures sit in its master's report — the one on screen now.
      final profile = context.read<UserProfileProvider>();
      next = {
        'kind': 'user',
        'id': d['id'],
        'name': d['name'],
        'username': d['username'],
        'master_id': _asMasterId ?? (profile.isMaster ? profile.master?.id : null),
      };
    }
    setState(() => _path = [..._path, next]);
    _fetchReport();
  }

  void _goTo(int index) {
    setState(() => _path = _path.sublist(0, index + 1));
    _fetchReport();
  }

  void _reset() {
    setState(() {
      _selectedRange = 'this_week';
      _customFrom = null;
      _customTo = null;
      _path = [
        {'kind': 'self'}
      ];
      _withOpening = false;
    });
    _fetchReport();
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_customFrom ?? DateTime.now()) : (_customTo ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: kBrandPrimary)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _customFrom = picked;
        } else {
          _customTo = picked;
        }
      });
    }
  }

  // ── PDF download ──

  Future<void> _downloadReport() async {
    if (_report == null) return;
    setState(() => _isDownloading = true);
    try {
      final pdf = _buildPdf(_report!);
      final bytes = await pdf.save();
      if (!mounted) return;
      await _showPdfOptionsSheet(bytes, _viewerName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  pw.Document _buildPdf(Map<String, dynamic> report) {
    final fmt = NumberFormat('#,##0.00');
    final view = _view;
    final targetName = _viewerName;

    pw.Widget table(String title, List<SettlementLine> rows) {
      final (sumPnl, sumBrk, sumTotal) = sectionTotals(rows);
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 10),
          pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.6),
              1: pw.FlexColumnWidth(1.2),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(children: [
                _pdfCell('Username', bold: true),
                _pdfCell('P&L', bold: true),
                _pdfCell('Brk', bold: true),
                _pdfCell('Total', bold: true),
              ]),
              for (final r in rows)
                pw.TableRow(children: [
                  _pdfCell(r.sub == null ? r.label : '${r.label}\n${r.sub}'),
                  _pdfCell(fmt.format(r.pnl)),
                  _pdfCell(fmt.format(r.brokerage)),
                  _pdfCell(fmt.format(r.total)),
                ]),
              pw.TableRow(children: [
                _pdfCell('TOTAL', bold: true),
                _pdfCell(fmt.format(sumPnl), bold: true),
                _pdfCell(fmt.format(sumBrk), bold: true),
                _pdfCell(fmt.format(sumTotal), bold: true),
              ]),
            ],
          ),
        ],
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Settlement Report', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(targetName, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
            pw.Text('Total Profit & Loss: ${fmt.format(view.header)}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            if (view.profit.isNotEmpty) table('PROFIT', view.profit),
            if (view.loss.isNotEmpty) table('LOSS', view.loss),
          ],
        ),
      ),
    );
    return doc;
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  Future<void> _showPdfOptionsSheet(Uint8List bytes, String targetName) async {
    final dateFmt = DateFormat('ddMMyyyy');
    final (from, to) = _resolveRange();
    final fileName = 'Settlement_${targetName.replaceAll(' ', '_')}_${dateFmt.format(from)}_${dateFmt.format(to)}.pdf';

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 24 + MediaQuery.of(ctx).viewPadding.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PDF Generated',
                style: TextStyle(fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightBold, color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            Text(fileName, style: const TextStyle(fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, color: kColorTextMuted)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final nav = Navigator.of(ctx);
                      Navigator.pop(ctx);
                      nav.push(MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: Text(fileName, style: const TextStyle(fontSize: 13, color: Colors.white), overflow: TextOverflow.ellipsis),
                            backgroundColor: kBrandPrimary,
                            foregroundColor: Colors.white,
                          ),
                          body: PdfPreview(
                            build: (_) => bytes,
                            allowSharing: true,
                            allowPrinting: true,
                            pdfFileName: fileName,
                            canChangeOrientation: false,
                            canChangePageFormat: false,
                          ),
                        ),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                      child: const Column(children: [
                        Icon(Icons.picture_as_pdf_rounded, size: 28, color: kBrandPrimary),
                        SizedBox(height: 6),
                        Text('View PDF', style: TextStyle(fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, color: kBrandPrimary)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        final dir = await getTemporaryDirectory();
                        final file = File('${dir.path}/$fileName');
                        await file.writeAsBytes(bytes);
                        await Share.shareXFiles([XFile(file.path)], text: 'Settlement Report - $targetName');
                        // Financial report PDFs shouldn't linger in app cache
                        // after the share sheet is done with them — a lost/
                        // resold device could otherwise leak old bills from
                        // temp storage indefinitely.
                        try {
                          if (await file.exists()) await file.delete();
                        } catch (_) {}
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red));
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                      child: const Column(children: [
                        Icon(Icons.share_rounded, size: 28, color: kBrandPrimary),
                        SizedBox(height: 6),
                        Text('Share', style: TextStyle(fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, color: kBrandPrimary)),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildControls(),
                    const SizedBox(height: 12),
                    _buildDownloadRow(),
                    const SizedBox(height: 12),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator(color: kBrandPrimary)),
                      )
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(children: [
                            Text(_error!, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeBody, fontFamily: kFontFamily)),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: _fetchReport,
                              child: const Text('Retry', style: TextStyle(color: kBrandPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                            ),
                          ]),
                        ),
                      )
                    else if (_report != null) ...[
                      if (_path.length > 1) ...[_buildPathBar(), const SizedBox(height: 8)],
                      Builder(builder: (_) {
                        final view = _view;
                        return Column(children: [
                          _buildTotalBar(view.header),
                          const SizedBox(height: 12),
                          _buildSection('PROFIT', view.profit, true),
                          const SizedBox(height: 12),
                          _buildSection('LOSS', view.loss, false),
                        ]);
                      }),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Icon(Icons.arrow_back, color: kColorTextPrimary, size: kIconSizeMedium),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Settlement Report',
                style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown(_selectedRange, _rangeOptions, (v) => setState(() => _selectedRange = v!), displayMap: _rangeLabels),
        if (_selectedRange == 'custom') ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: GestureDetector(onTap: () => _pickDate(true), child: _dateBox(_customFrom != null ? DateFormat('dd-MM-yyyy').format(_customFrom!) : 'From'))),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(onTap: () => _pickDate(false), child: _dateBox(_customTo != null ? DateFormat('dd-MM-yyyy').format(_customTo!) : 'To'))),
          ]),
        ],
        const SizedBox(height: 8),

        // Account dropdown — whose view is shown (me, or a client/sub-master under me).
        _buildDropdown(
          _path.length > 1 ? '${_path[1]['kind'] == 'user' ? 'User' : 'Master'}:${_path[1]['id']}' : '__self__',
          ['__self__', ..._entities.map((e) => '${e['type']}:${e['id']}')],
          (v) {
            setState(() {
              if (v == null || v == '__self__') {
                _path = [
                  {'kind': 'self'}
                ];
                return;
              }
              final e = _entities.firstWhere((x) => '${x['type']}:${x['id']}' == v, orElse: () => <String, dynamic>{});
              if (e.isEmpty) return;
              _path = [
                {'kind': 'self'},
                e['type'] == 'Master'
                    ? {'kind': 'master', 'id': '${e['id']}', 'name': e['name'], 'username': e['username']}
                    : {'kind': 'user', 'id': '${e['id']}', 'name': e['name'], 'username': e['username'], 'master_id': e['master_id']},
              ];
            });
          },
          displayMap: {
            '__self__': '${_selfLabel()} (me)',
            for (final e in _entities) '${e['type']}:${e['id']}': '${e['username']} — ${e['name'] ?? ''} (${e['type'] == 'Master' ? 'M' : 'C'})',
          },
        ),
        const SizedBox(height: 12),

        const Text('With Opening:', style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
        Row(children: [
          _radioOption('Yes', true),
          const SizedBox(width: 16),
          _radioOption('No', false),
        ]),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: _isLoading ? null : _fetchReport,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(10)),
                child: const Text('Search', style: TextStyle(color: Colors.white, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _reset,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBrandPrimary)),
                child: const Text('Reset', style: TextStyle(color: kBrandPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  String _selfLabel() {
    final profile = context.read<UserProfileProvider>();
    return profile.master?.username ?? profile.user?.username ?? 'My account';
  }

  /// Back + the drill-down path (me › gm11 › gm22 …); tapping a step returns to it.
  Widget _buildPathBar() {
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
      GestureDetector(
        onTap: () => _goTo(_path.length - 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFC7C7CC))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_back_ios_new, size: 12, color: kBrandPrimary),
            SizedBox(width: 4),
            Text('Back', style: TextStyle(color: kBrandPrimary, fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
          ]),
        ),
      ),
      for (var i = 0; i < _path.length; i++)
        GestureDetector(
          onTap: i == _path.length - 1 ? null : () => _goTo(i),
          child: Text(
            '${i > 0 ? '› ' : ''}${_path[i]['kind'] == 'self' ? _selfLabel() : _path[i]['username']}',
            style: TextStyle(
              color: i == _path.length - 1 ? kColorTextPrimary : kBrandPrimary,
              fontSize: kFontSizeCaption,
              fontFamily: kFontFamily,
              fontWeight: i == _path.length - 1 ? kFontWeightSemiBold : kFontWeightRegular,
            ),
          ),
        ),
    ]);
  }

  Widget _radioOption(String label, bool value) {
    return GestureDetector(
      onTap: () {
        setState(() => _withOpening = value);
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Radio<bool>(
          value: value,
          groupValue: _withOpening,
          activeColor: kBrandPrimary,
          onChanged: (v) => setState(() => _withOpening = v ?? false),
        ),
        Text(label, style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily)),
      ]),
    );
  }

  Widget _buildDownloadRow() {
    return GestureDetector(
      onTap: (_report == null || _isDownloading) ? null : _downloadReport,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.picture_as_pdf_outlined, size: kIconSizeMedium, color: Colors.black87),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Download Report', style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
          ),
          _isDownloading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kBrandPrimary))
              : const Icon(Icons.download_rounded, size: kIconSizeMedium, color: Colors.black54),
        ]),
      ),
    );
  }

  Widget _buildTotalBar(double totalPnl) {
    // This account's own result — My Brokerage + My Profit/Loss, shown rounded
    // like the reference.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Total Profit & Loss', style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: totalPnl >= 0 ? const Color(0x3334C759) : const Color(0x33FF3B30),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            totalPnl.toStringAsFixed(0),
            style: TextStyle(
              color: totalPnl >= 0 ? kColorBuy : kColorSell,
              fontSize: kFontSizeBody,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildSection(String title, List<SettlementLine> rows, bool isProfit) {
    final expanded = isProfit ? _profitExpanded : _lossExpanded;
    final headerColor = isProfit ? const Color(0xFFE8F2FE) : const Color(0xFFFCE9E9);
    final titleColor = isProfit ? const Color(0xFF1B74E4) : const Color(0xFFD9362A);

    final (sumPnl, sumBrk, sumTotal) = sectionTotals(rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            if (isProfit) {
              _profitExpanded = !_profitExpanded;
            } else {
              _lossExpanded = !_lossExpanded;
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: headerColor, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(title, style: TextStyle(color: titleColor, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
              Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: titleColor),
            ]),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 4),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(isProfit ? 'No profit entries' : 'No loss entries', style: const TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeBody, fontFamily: kFontFamily)),
            )
          else ...[
            _rowHeader(),
            for (final r in rows) _dataRow(r),
            _totalRow(sumPnl, sumBrk, sumTotal),
          ],
        ],
      ],
    );
  }

  Widget _rowHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text('Username', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
        Expanded(child: Text('P&L', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
        Expanded(child: Text('Brk', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
        Expanded(child: Text('Total', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
      ]),
    );
  }

  Widget _dataRow(SettlementLine r) {
    final row = Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD1D1D6), width: 0.5))),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(children: [
            Text(r.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: r.kind == 'admin' ? kColorSell : kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily)),
            if (r.sub != null)
              Text(r.sub!, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
          ]),
        ),
        Expanded(child: Text(r.pnl.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily))),
        Expanded(child: Text(r.brokerage.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily))),
        Expanded(child: Text(r.total.toStringAsFixed(2), textAlign: TextAlign.center, style: TextStyle(color: r.total >= 0 ? kColorBuy : kColorSell, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
      ]),
    );
    // A downline row opens that account's own view.
    if (r.drill == null) return row;
    return InkWell(onTap: () => _drill(r), child: row);
  }

  Widget _totalRow(double sumPnl, double sumBrk, double sumTotal) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        const Expanded(child: Text('TOTAL', textAlign: TextAlign.center, style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        Expanded(child: Text(sumPnl.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        Expanded(child: Text(sumBrk.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        Expanded(child: Text(sumTotal.toStringAsFixed(2), textAlign: TextAlign.center, style: TextStyle(color: sumTotal >= 0 ? kColorBuy : kColorSell, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightBold))),
      ]),
    );
  }

  Widget _buildDropdown(String value, List<String> items, ValueChanged<String?> onChanged, {Map<String, String>? displayMap}) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC7C7CC)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF8E8E93)),
          style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightRegular),
          items: items.map((k) => DropdownMenuItem(value: k, child: Text(displayMap?[k] ?? k, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _dateBox(String text) {
    final isPlaceholder = text == 'From' || text == 'To';
    return Container(
      height: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFC7C7CC))),
      child: Row(children: [
        Icon(Icons.calendar_today, size: kIconSizeSmall, color: isPlaceholder ? const Color(0xFFCBD5E1) : kBrandPrimary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: isPlaceholder ? const Color(0xFFCBD5E1) : kColorTextPrimary, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
