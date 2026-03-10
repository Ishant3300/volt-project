import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class PdfReportService {
  static final _fmt = NumberFormat('#,##0.00');
  static final _dateFmt = DateFormat('dd-MMM hh:mm:ss a');
  static final _dayFmt = DateFormat('dd MMM yyyy');

  static pw.Document generateDefaultReport(Map<String, dynamic> data) {
    final pdf = pw.Document();
    final userName = data['user_name'] ?? 'Unknown';
    final from = DateTime.parse(data['from']);
    final to = DateTime.parse(data['to']);
    final instruments = (data['instruments'] as List?) ?? [];
    final summary = data['summary'] ?? {};
    final carryForward = (data['carry_forward'] as List?) ?? [];

    final headerStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final cellStyle = const pw.TextStyle(fontSize: 7);
    final titleStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);

    // Build instrument sections
    final List<pw.Widget> content = [];

    // Title header
    content.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        color: PdfColor.fromHex('#7B9CC0'),
        child: pw.Column(children: [
          pw.Text(userName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          pw.SizedBox(height: 2),
          pw.Text(
            'General Summary From ${_dayFmt.format(from)} To ${_dayFmt.format(to)}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.white),
          ),
        ]),
      ),
    );
    content.add(pw.SizedBox(height: 10));

    // Per-instrument sections
    for (final instr in instruments) {
      final exchange = instr['exchange'] ?? '';
      final symbol = instr['tradingsymbol'] ?? '';
      final buys = (instr['buys'] as List?) ?? [];
      final sells = (instr['sells'] as List?) ?? [];
      final pnl = (instr['pnl'] as num?)?.toDouble() ?? 0;
      final brokerage = (instr['brokerage'] as num?)?.toDouble() ?? 0;
      final netPnl = (instr['net_pnl'] as num?)?.toDouble() ?? 0;
      final totalBuyQty = (instr['total_buy_qty'] as num?)?.toDouble() ?? 0;
      final totalSellQty = (instr['total_sell_qty'] as num?)?.toDouble() ?? 0;
      final avgBuyPrice = (instr['avg_buy_price'] as num?)?.toDouble() ?? 0;
      final avgSellPrice = (instr['avg_sell_price'] as num?)?.toDouble() ?? 0;
      final totalBuyVol = (instr['total_buy_vol'] as num?)?.toDouble() ?? 0;
      final totalSellVol = (instr['total_sell_vol'] as num?)?.toDouble() ?? 0;

      // Instrument title
      content.add(pw.Text('$exchange  $symbol', style: titleStyle));
      content.add(pw.SizedBox(height: 4));

      // Side-by-side buy/sell tables
      content.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Buy table
          pw.Expanded(child: _buildSideTable('B', buys, totalBuyQty, avgBuyPrice, totalBuyVol, headerStyle, cellStyle)),
          pw.SizedBox(width: 8),
          // Sell table
          pw.Expanded(child: _buildSideTable('S', sells, totalSellQty, avgSellPrice, totalSellVol, headerStyle, cellStyle)),
        ],
      ));

      // P&L rows below
      content.add(pw.SizedBox(height: 2));
      content.add(_pnlRow('', _fmt.format(pnl.abs()), pnl < 0, cellStyle));
      content.add(_pnlRow('Br', '+ ${_fmt.format(brokerage)}', false, cellStyle));
      content.add(_pnlRow(netPnl < 0 ? '( L )' : '( P )', _fmt.format(netPnl.abs()), netPnl < 0, cellStyle));
      content.add(pw.SizedBox(height: 12));
    }

    // Summary section
    content.add(pw.SizedBox(height: 8));
    content.add(pw.Text('Summary', style: titleStyle));
    content.add(pw.SizedBox(height: 4));
    content.add(_buildSummaryTable(instruments, summary, headerStyle, cellStyle));

    // Carry forward section
    if (carryForward.isNotEmpty) {
      content.add(pw.SizedBox(height: 12));
      content.add(pw.Text('Carry Forward', style: titleStyle));
      content.add(pw.SizedBox(height: 4));
      content.add(_buildCarryForwardTable(carryForward, headerStyle, cellStyle));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => content,
      ),
    );

    return pdf;
  }

  static pw.Widget _buildSideTable(String side, List entries, double totalQty, double avgPrice, double totalVol, pw.TextStyle hs, pw.TextStyle cs) {
    final headerBg = PdfColor.fromHex('#C0C0C0');

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [
          _cell('Date', hs), _cell('${side} Qty', hs), _cell('Price', hs), _cell('${side} Vol.', hs),
        ],
      ),
    ];

    for (final e in entries) {
      final date = e['date'] is String ? DateTime.parse(e['date']) : e['date'] as DateTime;
      rows.add(pw.TableRow(children: [
        _cell(_dateFmt.format(date), cs),
        _cell(_fmt.format((e['qty'] as num).toDouble()), cs),
        _cell(_fmt.format((e['price'] as num).toDouble()), cs),
        _cell(_fmt.format((e['volume'] as num).toDouble()), cs),
      ]));
    }

    // Total row
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      children: [
        _cell('Total', hs), _cell(_fmt.format(totalQty), hs), _cell(_fmt.format(avgPrice), hs), _cell(_fmt.format(totalVol), hs),
      ],
    ));

    return pw.Table(
      border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: rows,
    );
  }

  static pw.Widget _cell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Text(text, style: style),
    );
  }

  static pw.Widget _pnlRow(String label, String value, bool isLoss, pw.TextStyle cs) {
    final color = isLoss ? PdfColors.red : PdfColors.black;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(right: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          if (label.isNotEmpty) pw.Text(label, style: cs.copyWith(color: isLoss ? PdfColors.red : PdfColors.black)),
          if (label.isNotEmpty) pw.SizedBox(width: 12),
          pw.Text(isLoss ? '- $value' : value, style: cs.copyWith(color: color)),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryTable(List instruments, Map<String, dynamic> summary, pw.TextStyle hs, pw.TextStyle cs) {
    final headerBg = PdfColor.fromHex('#C0C0C0');
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [_cell('Exchange', hs), _cell('Script', hs), _cell('Total', hs), _cell('Br', hs), _cell('Net', hs)],
      ),
    ];

    for (final i in instruments) {
      final pnl = (i['pnl'] as num?)?.toDouble() ?? 0;
      final br = (i['brokerage'] as num?)?.toDouble() ?? 0;
      final net = (i['net_pnl'] as num?)?.toDouble() ?? 0;
      rows.add(pw.TableRow(children: [
        _cell(i['exchange'] ?? '', cs),
        _cell(i['tradingsymbol'] ?? '', cs),
        _cell('${pnl < 0 ? '- ' : ''}${_fmt.format(pnl.abs())}', cs),
        _cell(_fmt.format(br), cs),
        _cell('${net < 0 ? '- ' : ''}${_fmt.format(net.abs())}', cs),
      ]));
    }

    final totalPnl = (summary['total_pnl'] as num?)?.toDouble() ?? 0;
    final totalBr = (summary['total_brokerage'] as num?)?.toDouble() ?? 0;
    final netPnl = (summary['net_pnl'] as num?)?.toDouble() ?? 0;

    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      children: [
        _cell('Total', hs), _cell('', cs),
        _cell('${totalPnl < 0 ? '-' : ''}${_fmt.format(totalPnl.abs())}',
            hs.copyWith(color: totalPnl < 0 ? PdfColors.red : PdfColors.black)),
        _cell(_fmt.format(totalBr), hs.copyWith(color: PdfColors.red)),
        _cell('${netPnl < 0 ? '-' : ''}${_fmt.format(netPnl.abs())}',
            hs.copyWith(color: netPnl < 0 ? PdfColors.red : PdfColors.black)),
      ],
    ));

    return pw.Table(
      border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1.5),
      },
      children: rows,
    );
  }

  static pw.Widget _buildCarryForwardTable(List carryForward, pw.TextStyle hs, pw.TextStyle cs) {
    final headerBg = PdfColor.fromHex('#C0C0C0');
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [_cell('Exchange', hs), _cell('Script', hs), _cell('Type', hs), _cell('Quantity', hs), _cell('Price', hs)],
      ),
    ];

    for (final cf in carryForward) {
      final isBuy = cf['type'] == 'Buy';
      rows.add(pw.TableRow(children: [
        _cell(cf['exchange'] ?? '', cs.copyWith(color: isBuy ? PdfColors.blue : PdfColors.red)),
        _cell(cf['tradingsymbol'] ?? '', cs.copyWith(color: isBuy ? PdfColors.blue : PdfColors.red)),
        _cell(cf['type'] ?? '', cs.copyWith(color: isBuy ? PdfColors.blue : PdfColors.red)),
        _cell(_fmt.format((cf['quantity'] as num).toDouble()), cs),
        _cell(_fmt.format((cf['price'] as num).toDouble()), cs),
      ]));
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1.5),
      },
      children: rows,
    );
  }

  // ===================== ADVANCED (Live M2M) REPORT =====================

  static pw.Document generateAdvancedReport(Map<String, dynamic> data) {
    final pdf = pw.Document();
    final userName = data['user_name'] ?? 'Unknown';
    final from = DateTime.parse(data['from']);
    final to = DateTime.parse(data['to']);
    final instruments = (data['instruments'] as List?) ?? [];
    final summary = data['summary'] ?? {};
    final carryForward = (data['carry_forward'] as List?) ?? [];

    final hs = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final cs = const pw.TextStyle(fontSize: 7);
    final titleStyle = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black);

    final List<pw.Widget> content = [];

    // Title
    content.add(pw.Center(child: pw.Text('Live M2M Report', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))));
    content.add(pw.SizedBox(height: 4));
    content.add(pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(userName, style: const pw.TextStyle(fontSize: 9)),
        pw.Text('From ${_dayFmt.format(from)} To ${_dayFmt.format(to)}', style: const pw.TextStyle(fontSize: 9)),
      ],
    ));
    content.add(pw.SizedBox(height: 10));

    // Per-instrument sections
    for (final instr in instruments) {
      final exchange = instr['exchange'] ?? '';
      final symbol = instr['tradingsymbol'] ?? '';
      final allTrades = (instr['all_trades'] as List?) ?? [];
      final pnl = (instr['pnl'] as num?)?.toDouble() ?? 0;
      final brokerage = (instr['brokerage'] as num?)?.toDouble() ?? 0;
      final netPnl = (instr['net_pnl'] as num?)?.toDouble() ?? 0;
      final totalBuyQty = (instr['total_buy_qty'] as num?)?.toDouble() ?? 0;
      final totalSellQty = (instr['total_sell_qty'] as num?)?.toDouble() ?? 0;

      // Instrument header
      content.add(pw.Center(child: pw.Text('$exchange  $symbol', style: titleStyle)));
      content.add(pw.SizedBox(height: 4));

      // Build the unified table
      final headerBg = PdfColor.fromHex('#CCCCDD');
      final totalBg = PdfColor.fromHex('#CCCCDD');
      final netBg = PdfColor.fromHex('#FFFFCC');

      final rows = <pw.TableRow>[
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _cell('Date', hs), _cell('Type', hs), _cell('B Qty', hs),
            _cell('S Qty', hs), _cell('Rate', hs), _cell('Br', hs), _cell('Net', hs),
          ],
        ),
      ];

      // Compute running net for each trade
      double avgBuyPrice = 0;
      double totalBoughtQty = 0;

      for (final t in allTrades) {
        final date = t['date'] is String ? DateTime.parse(t['date']) : t['date'];
        final type = t['type'] ?? '';
        final bQty = (t['buy_qty'] as num?)?.toDouble() ?? 0;
        final sQty = (t['sell_qty'] as num?)?.toDouble() ?? 0;
        final rate = (t['rate'] as num?)?.toDouble() ?? 0;
        final br = (t['brokerage'] as num?)?.toDouble() ?? 0;

        double net = 0;
        if (type == 'BUY') {
          // Accumulate buy cost
          totalBoughtQty += bQty;
          avgBuyPrice = ((avgBuyPrice * (totalBoughtQty - bQty)) + (rate * bQty)) / totalBoughtQty;
          net = 0; // Buy trades show 0 net
        } else {
          // Sell: compute P&L against avg buy
          net = (rate - avgBuyPrice) * sQty;
          totalBoughtQty -= sQty;
          if (totalBoughtQty < 0) totalBoughtQty = 0;
        }

        final typeColor = type == 'BUY' ? PdfColors.blue : PdfColors.red;

        rows.add(pw.TableRow(children: [
          _cell(_dateFmt.format(date), cs),
          _cell(type == 'BUY' ? 'Buy' : 'Sell', cs.copyWith(color: typeColor)),
          _cell(bQty > 0 ? _fmt.format(bQty) : '', cs),
          _cell(sQty > 0 ? _fmt.format(sQty) : '', cs),
          _cell(_fmt.format(rate), cs),
          _cell(_fmt.format(br), cs),
          _cell(_fmt.format(net), cs.copyWith(color: net < 0 ? PdfColors.red : PdfColors.black)),
        ]));
      }

      // Script wise total row
      rows.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: totalBg),
        children: [
          _cell('Script wise total :', hs), _cell('', cs),
          _cell(_fmt.format(totalBuyQty), hs),
          _cell(_fmt.format(totalSellQty), hs),
          _cell('', cs),
          _cell(_fmt.format(brokerage), hs),
          _cell(_fmt.format(pnl), hs.copyWith(color: pnl < 0 ? PdfColors.red : PdfColors.black)),
        ],
      ));

      // Total row (net including brokerage)
      rows.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: netBg),
        children: [
          _cell('', cs), _cell('', cs), _cell('', cs),
          _cell('', cs), _cell('Total:', hs),
          _cell('', cs),
          _cell(_fmt.format(netPnl), hs.copyWith(color: netPnl < 0 ? PdfColors.red : PdfColors.black)),
        ],
      ));

      content.add(pw.Table(
        border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.5),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1),
          4: const pw.FlexColumnWidth(1.3),
          5: const pw.FlexColumnWidth(1),
          6: const pw.FlexColumnWidth(1.5),
        },
        children: rows,
      ));
      content.add(pw.SizedBox(height: 14));
    }

    // Summary
    content.add(pw.SizedBox(height: 6));
    content.add(_buildAdvancedSummaryTable(instruments, summary, hs, cs));

    // Carry Forward
    if (carryForward.isNotEmpty) {
      content.add(pw.SizedBox(height: 12));
      content.add(_buildAdvancedCarryForwardTable(carryForward, hs, cs));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => content,
      ),
    );

    return pdf;
  }

  static pw.Widget _buildAdvancedSummaryTable(List instruments, Map<String, dynamic> summary, pw.TextStyle hs, pw.TextStyle cs) {
    final headerBg = PdfColor.fromHex('#CCCCDD');
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [
          _cell('', hs),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: pw.Center(child: pw.Text('Summary', style: hs)),
          ),
          _cell('', hs), _cell('', hs), _cell('', hs),
        ],
      ),
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [_cell('Exchange', hs), _cell('Script', hs), _cell('Total', hs), _cell('Br', hs), _cell('Net', hs)],
      ),
    ];

    for (final i in instruments) {
      final pnl = (i['pnl'] as num?)?.toDouble() ?? 0;
      final br = (i['brokerage'] as num?)?.toDouble() ?? 0;
      final net = (i['net_pnl'] as num?)?.toDouble() ?? 0;
      rows.add(pw.TableRow(children: [
        _cell(i['exchange'] ?? '', cs),
        _cell(i['tradingsymbol'] ?? '', cs),
        _cell('${pnl < 0 ? '-' : ''}${_fmt.format(pnl.abs())}', cs.copyWith(color: pnl < 0 ? PdfColors.red : PdfColors.black)),
        _cell(_fmt.format(br), cs),
        _cell('${net < 0 ? '-' : ''}${_fmt.format(net.abs())}', cs.copyWith(color: net < 0 ? PdfColors.red : PdfColors.black)),
      ]));
    }

    final totalPnl = (summary['total_pnl'] as num?)?.toDouble() ?? 0;
    final totalBr = (summary['total_brokerage'] as num?)?.toDouble() ?? 0;
    final netPnl = (summary['net_pnl'] as num?)?.toDouble() ?? 0;

    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      children: [
        _cell('Total', hs), _cell('', cs),
        _cell('${totalPnl < 0 ? '-' : ''}${_fmt.format(totalPnl.abs())}',
            hs.copyWith(color: totalPnl < 0 ? PdfColors.red : PdfColors.black)),
        _cell(_fmt.format(totalBr), hs.copyWith(color: PdfColors.red)),
        _cell('${netPnl < 0 ? '-' : ''}${_fmt.format(netPnl.abs())}',
            hs.copyWith(color: netPnl < 0 ? PdfColors.red : PdfColors.black)),
      ],
    ));

    return pw.Table(
      border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1.5),
      },
      children: rows,
    );
  }

  static pw.Widget _buildAdvancedCarryForwardTable(List carryForward, pw.TextStyle hs, pw.TextStyle cs) {
    final headerBg = PdfColor.fromHex('#C0C0C0');
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [
          _cell('', hs),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: pw.Center(child: pw.Text('Carry Forward', style: hs)),
          ),
          _cell('', hs), _cell('', hs), _cell('', hs),
        ],
      ),
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [_cell('Exchange', hs), _cell('Script', hs), _cell('Type', hs), _cell('Qty', hs), _cell('Net', hs)],
      ),
    ];

    for (final cf in carryForward) {
      final isBuy = cf['type'] == 'Buy';
      final color = isBuy ? PdfColors.blue : PdfColors.red;
      rows.add(pw.TableRow(children: [
        _cell(cf['exchange'] ?? '', cs.copyWith(color: color)),
        _cell(cf['tradingsymbol'] ?? '', cs.copyWith(color: color)),
        _cell(cf['type'] ?? '', cs.copyWith(color: color)),
        _cell(_fmt.format((cf['quantity'] as num).toDouble()), cs),
        _cell(_fmt.format((cf['price'] as num).toDouble()), cs),
      ]));
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1.5),
      },
      children: rows,
    );
  }
}
