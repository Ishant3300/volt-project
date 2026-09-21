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

/// Settlement Report — GET /master/settlement-report. Lists whoever is
/// selected (a specific client/sub-master under the viewer, or the
/// viewer's own team by default) with each of THEIR own direct
/// clients/sub-masters' own P&L, brokerage, and net total for the picked
/// date range, split into who profited and who lost. Every real row's
/// P&L/Brk/Total is deliberately raw — no sharing-cascade or
/// house-perspective sign flip, that account's own real result, as the
/// backend computes it (settlementReportService.js).
///
/// The caller's own post-cut share appears as three extra ROWS —
/// "Admin" (what flows PAST the caller further up the chain), "My
/// Profit/Loss", and "My Brokerage" — bucketed into Profit or Loss by
/// their own sign, same as every real row (see _rowsWithCascade). The top
/// "Total Profit & Loss" tile is the caller's own combined net
/// (caller_total_pnl), not the raw sum of every row.
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

  // Target entity (a user or a sub-master under the viewer)
  List<Map<String, dynamic>> _entities = []; // {id, name, username, type: 'User'|'Master'}
  Map<String, dynamic>? _selectedEntity;

  // With Opening
  bool _withOpening = false;

  bool _profitExpanded = true;
  bool _lossExpanded = true;

  Map<String, dynamic>? _report;

  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    if (widget.user != null) {
      _selectedEntity = {
        'id': widget.user!.id,
        'name': widget.user!.name,
        'username': widget.user!.username,
        'type': 'User',
      };
    } else if (widget.master != null) {
      _selectedEntity = {
        'id': widget.master!.id,
        'name': widget.master!.name,
        'username': widget.master!.username,
        'type': 'Master',
      };
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
        final prevSunday = thisMonday.subtract(const Duration(seconds: 1));
        return (prevMonday, prevSunday);
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
          merged.add({'id': u['id'] ?? u['_id'], 'name': u['name'], 'username': u['username'], 'type': 'User'});
        }
      }
      if (results[1].statusCode == 200) {
        final body = jsonDecode(results[1].body);
        final nested = body['data'];
        final List list = nested is Map ? (nested['masters'] ?? []) : (nested ?? []);
        for (final m in list) {
          merged.add({'id': m['id'] ?? m['_id'], 'name': m['name'], 'username': m['username'], 'type': 'Master'});
        }
      }
      if (mounted) setState(() => _entities = merged);
    } catch (_) {
      // Non-fatal — the dropdown just stays empty/pre-selected; the report itself can still load.
    }
  }

  Future<void> _fetchReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final (from, to) = _resolveRange();
      final token = await _storage.getToken();
      var url = '/master/settlement-report?from=${_fmtIso(from)}&to=${_fmtIso(to)}'
          '&with_opening=$_withOpening';
      if (_selectedEntity != null) {
        url += '&target_id=${_selectedEntity!['id']}';
      }
      final res = await ApiService(backendUrl).get(url, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() {
            _report = Map<String, dynamic>.from(body['data'] ?? {});
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = body['message'] ?? 'Failed to load report';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Failed to load report';
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

  // The caller's own post-cut share, broken out as three extra line-items
  // (bucketed into Profit/Loss by their own sign, same as every real row)
  // instead of extra columns — matches the reference terminal's own layout
  // and the web portal's identical restructuring. Summed across EVERY real
  // row regardless of which section it's in: these represent what the
  // caller keeps/passes on from their WHOLE downline's combined result, not
  // a per-section figure. `username` (not `name`) carries the label since
  // _dataRow/_pdfCell only ever render `r['username']`.
  (List<Map<String, dynamic>>, List<Map<String, dynamic>>) _rowsWithCascade(
      List<Map<String, dynamic>> profit, List<Map<String, dynamic>> loss) {
    final all = [...profit, ...loss];
    final hasCascade = all.any((r) => r['caller_total'] != null);
    if (!hasCascade) return (profit, loss);

    double sum(num? Function(Map<String, dynamic>) get) =>
        all.fold(0.0, (s, r) => s + (get(r)?.toDouble() ?? 0));

    final admin = <String, dynamic>{
      'id': 'admin',
      'username': 'Admin',
      'pnl': sum((r) => r['owed_upward_pnl'] as num?),
      'brokerage': sum((r) => r['owed_upward_brokerage'] as num?),
      'total': sum((r) => r['owed_upward_total'] as num?),
    };
    final myPnl = <String, dynamic>{
      'id': 'my-pnl',
      'username': 'My Profit/Loss',
      'pnl': 0.0,
      'brokerage': 0.0,
      'total': sum((r) => r['caller_pnl'] as num?),
    };
    final myBrokerage = <String, dynamic>{
      'id': 'my-brokerage',
      'username': 'My Brokerage',
      'pnl': 0.0,
      'brokerage': 0.0,
      'total': sum((r) => r['caller_brokerage'] as num?),
    };

    // Skip a line-item that's genuinely zero across the board (e.g.
    // "Admin" when the caller IS Admin — nothing ever flows past them)
    // rather than clutter every report with a permanent 0.00 row.
    final synthetic = [admin, myPnl, myBrokerage]
        .where((r) => (r['pnl'] as double) != 0 || (r['brokerage'] as double) != 0 || (r['total'] as double) != 0)
        .toList();

    return (
      [...profit, ...synthetic.where((r) => (r['total'] as double) >= 0)],
      [...loss, ...synthetic.where((r) => (r['total'] as double) < 0)],
    );
  }

  void _reset() {
    setState(() {
      _selectedRange = 'this_week';
      _customFrom = null;
      _customTo = null;
      _selectedEntity = null;
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
      final targetName = _report!['target']?['name'] ?? _report!['target']?['username'] ?? 'Settlement';
      await _showPdfOptionsSheet(bytes, targetName);
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
    final (profit, loss) = _rowsWithCascade(
      List<Map<String, dynamic>>.from(report['profit'] ?? []),
      List<Map<String, dynamic>>.from(report['loss'] ?? []),
    );
    final totalPnl = (report['caller_total_pnl'] as num?)?.toDouble() ?? (report['total_pnl'] as num?)?.toDouble() ?? 0;
    final targetName = report['target']?['name'] ?? report['target']?['username'] ?? '';

    pw.Widget table(String title, List<Map<String, dynamic>> rows) {
      double sumPnl = 0, sumBrk = 0, sumTotal = 0;
      for (final r in rows) {
        sumPnl += (r['pnl'] as num?)?.toDouble() ?? 0;
        sumBrk += (r['brokerage'] as num?)?.toDouble() ?? 0;
        sumTotal += (r['total'] as num?)?.toDouble() ?? 0;
      }
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 10),
          pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
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
                  _pdfCell('${r['username'] ?? ''}'),
                  _pdfCell(fmt.format((r['pnl'] as num?)?.toDouble() ?? 0)),
                  _pdfCell(fmt.format((r['brokerage'] as num?)?.toDouble() ?? 0)),
                  _pdfCell(fmt.format((r['total'] as num?)?.toDouble() ?? 0)),
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
            pw.Text('$targetName', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
            pw.Text('Total Profit & Loss: ${fmt.format(totalPnl)}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            if (profit.isNotEmpty) table('PROFIT', profit),
            if (loss.isNotEmpty) table('LOSS', loss),
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
            Text(fileName, style: const TextStyle(fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, color: Color(0xFF94A3B8))),
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
                      _buildTotalBar(),
                      const SizedBox(height: 12),
                      Builder(builder: (_) {
                        final (profitRows, lossRows) = _rowsWithCascade(
                          List<Map<String, dynamic>>.from(_report!['profit'] ?? []),
                          List<Map<String, dynamic>>.from(_report!['loss'] ?? []),
                        );
                        return Column(children: [
                          _buildSection('PROFIT', profitRows, true),
                          const SizedBox(height: 12),
                          _buildSection('LOSS', lossRows, false),
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
              child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Settlement Report',
                style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
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

        // Entity dropdown — user or sub-master under the viewer.
        _buildDropdown(
          _selectedEntity != null ? '${_selectedEntity!['type']}:${_selectedEntity!['id']}' : '__self__',
          ['__self__', ..._entities.map((e) => '${e['type']}:${e['id']}')],
          (v) {
            setState(() {
              if (v == '__self__') {
                _selectedEntity = null;
              } else {
                _selectedEntity = _entities.firstWhere(
                  (e) => '${e['type']}:${e['id']}' == v,
                  orElse: () => <String, dynamic>{},
                );
              }
            });
          },
          displayMap: {
            '__self__': 'My own team',
            for (final e in _entities) '${e['type']}:${e['id']}': '${e['name'] ?? e['username']}',
          },
        ),
        const SizedBox(height: 12),

        const Text('With Opening:', style: TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
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
        Text(label, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily)),
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
            child: Text('Download Report', style: TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
          ),
          _isDownloading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kBrandPrimary))
              : const Icon(Icons.download_rounded, size: kIconSizeMedium, color: Colors.black54),
        ]),
      ),
    );
  }

  Widget _buildTotalBar() {
    // The caller's own combined net (caller_total_pnl — "My Profit/Loss" +
    // "My Brokerage" combined below), not the raw sum of every row's total —
    // matches the reference terminal's own top tile and the web portal's
    // identical fix. Falls back to the raw total only if caller identity
    // isn't known (shouldn't happen in practice, but keeps the tile from
    // going blank).
    final totalPnl = (_report!['caller_total_pnl'] as num?)?.toDouble() ?? (_report!['total_pnl'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Total Profit & Loss', style: TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: totalPnl >= 0 ? const Color(0x3334C759) : const Color(0x33FF3B30),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            totalPnl.toStringAsFixed(0),
            style: TextStyle(
              color: totalPnl >= 0 ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
              fontSize: kFontSizeBody,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> rows, bool isProfit) {
    final expanded = isProfit ? _profitExpanded : _lossExpanded;
    final headerColor = isProfit ? const Color(0xFFE8F2FE) : const Color(0xFFFCE9E9);
    final titleColor = isProfit ? const Color(0xFF1B74E4) : const Color(0xFFD9362A);

    double sumPnl = 0, sumBrk = 0, sumTotal = 0;
    for (final r in rows) {
      sumPnl += (r['pnl'] as num?)?.toDouble() ?? 0;
      sumBrk += (r['brokerage'] as num?)?.toDouble() ?? 0;
      sumTotal += (r['total'] as num?)?.toDouble() ?? 0;
    }

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

  Widget _dataRow(Map<String, dynamic> r) {
    final pnl = (r['pnl'] as num?)?.toDouble() ?? 0;
    final brk = (r['brokerage'] as num?)?.toDouble() ?? 0;
    final total = (r['total'] as num?)?.toDouble() ?? 0;
    final username = '${r['username'] ?? ''}';
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD1D1D6), width: 0.5))),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(child: Text(username, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily))),
        Expanded(child: Text(pnl.toStringAsFixed(2), textAlign: TextAlign.center, style: TextStyle(color: pnl >= 0 ? const Color(0xFF34C759) : const Color(0xFFFF3B30), fontSize: kFontSizeBody, fontFamily: kFontFamily))),
        Expanded(child: Text(brk.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily))),
        Expanded(child: Text(total.toStringAsFixed(2), textAlign: TextAlign.center, style: TextStyle(color: total >= 0 ? const Color(0xFF34C759) : const Color(0xFFFF3B30), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
      ]),
    );
  }

  Widget _totalRow(double sumPnl, double sumBrk, double sumTotal) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        const Expanded(child: Text('TOTAL', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        Expanded(child: Text(sumPnl.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        Expanded(child: Text(sumBrk.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        Expanded(child: Text(sumTotal.toStringAsFixed(2), textAlign: TextAlign.center, style: TextStyle(color: sumTotal >= 0 ? const Color(0xFF34C759) : const Color(0xFFFF3B30), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightBold))),
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
          style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightRegular),
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
        Expanded(child: Text(text, style: TextStyle(color: isPlaceholder ? const Color(0xFFCBD5E1) : Colors.black, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
