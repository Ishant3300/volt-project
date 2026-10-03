import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../config/app_brand.dart';

class PdfReportService {
  static final _fmt = NumberFormat('#,##0.00');
  // Display times in IST (UTC+05:30)
  static final _dateFmt = DateFormat('dd-MMM hh:mm:ss a');
  static final _dayFmt = DateFormat('dd MMM yyyy');

  /// Parse a date value and convert to IST (UTC+05:30).
  /// Accepts a DateTime or a date string (ISO 8601).
  /// Strings with Z suffix are UTC and get +05:30 added explicitly.
  /// Strings without Z are treated as already in IST (local time).
  static DateTime _parseToIST(dynamic dateVal) {
    try {
      final DateTime date;
      if (dateVal is DateTime) {
        date = dateVal;
      } else {
        date = DateTime.parse(dateVal.toString());
      }
      // UTC → add IST offset explicitly (device timezone independent)
      if (date.isUtc) {
        return date.add(const Duration(hours: 5, minutes: 30));
      }
      return date; // already local/IST
    } catch (_) {
      return DateTime.now();
    }
  }

  static pw.Document generateDefaultReport(Map<String, dynamic> data) {
    final pdf = pw.Document();
    final userName = data['user_name'] ?? 'Unknown';
    final from = DateTime.parse(data['from']);
    final to = DateTime.parse(data['to']);
    final instruments = (data['instruments'] as List?) ?? [];
    final summary = data['summary'] ?? {};
    final carryForward = (data['carry_forward'] as List?) ?? [];

    final headerStyle =
        pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final cellStyle = const pw.TextStyle(fontSize: 7);
    final titleStyle =
        pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);

    final List<pw.Widget> content = [];

    content.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        color: PdfColor.fromHex('#7B9CC0'),
        child: pw.Column(children: [
          pw.Text(userName,
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white)),
          pw.SizedBox(height: 2),
          pw.Text(
            'General Summary From ${_dayFmt.format(from)} To ${_dayFmt.format(to)}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.white),
          ),
        ]),
      ),
    );
    content.add(pw.SizedBox(height: 10));

    for (final instr in instruments) {
      final exchange = instr['exchange'] ?? '';
      final symbol = instr['display_name'] ?? instr['tradingsymbol'] ?? '';
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

      content.add(pw.Text('$exchange  $symbol', style: titleStyle));
      content.add(pw.SizedBox(height: 4));

      content.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              child: _buildSideTable('B', buys, totalBuyQty, avgBuyPrice,
                  totalBuyVol, headerStyle, cellStyle)),
          pw.SizedBox(width: 8),
          pw.Expanded(
              child: _buildSideTable('S', sells, totalSellQty, avgSellPrice,
                  totalSellVol, headerStyle, cellStyle)),
        ],
      ));

      content.add(pw.SizedBox(height: 2));
      content.add(_pnlRow('', _fmt.format(pnl.abs()), pnl < 0, cellStyle));
      content
          .add(_pnlRow('Br', '+ ${_fmt.format(brokerage)}', false, cellStyle));
      content.add(_pnlRow(netPnl < 0 ? '( L )' : '( P )',
          _fmt.format(netPnl.abs()), netPnl < 0, cellStyle));
      content.add(pw.SizedBox(height: 12));
    }

    content.add(pw.SizedBox(height: 8));
    content.add(pw.Text('Summary', style: titleStyle));
    content.add(pw.SizedBox(height: 4));
    content
        .add(_buildSummaryTable(instruments, summary, headerStyle, cellStyle));

    if (carryForward.isNotEmpty) {
      content.add(pw.SizedBox(height: 12));
      content.add(pw.Text('Carry Forward', style: titleStyle));
      content.add(pw.SizedBox(height: 4));
      content
          .add(_buildCarryForwardTable(carryForward, headerStyle, cellStyle));
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

  static pw.Widget _buildSideTable(String side, List entries, double totalQty,
      double avgPrice, double totalVol, pw.TextStyle hs, pw.TextStyle cs) {
    final headerBg = PdfColor.fromHex('#C0C0C0');

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [
          _cell('Date', hs),
          _cell('${side} Qty', hs),
          _cell('Price', hs),
          _cell('${side} Vol.', hs),
        ],
      ),
    ];

    for (final e in entries) {
      final date = _parseToIST(e['date']);
      rows.add(pw.TableRow(children: [
        _cell(_dateFmt.format(date), cs),
        _cell(_fmt.format((e['qty'] as num).toDouble()), cs),
        _cell(_fmt.format((e['price'] as num).toDouble()), cs),
        _cell(_fmt.format((e['volume'] as num).toDouble()), cs),
      ]));
    }

    rows.add(pw.TableRow(
      decoration:
          pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      children: [
        _cell('Total', hs),
        _cell(_fmt.format(totalQty), hs),
        _cell(_fmt.format(avgPrice), hs),
        _cell(_fmt.format(totalVol), hs),
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

  static pw.Widget _pnlRow(
      String label, String value, bool isLoss, pw.TextStyle cs) {
    final color = isLoss ? PdfColors.red : PdfColors.black;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(right: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          if (label.isNotEmpty)
            pw.Text(label,
                style: cs.copyWith(
                    color: isLoss ? PdfColors.red : PdfColors.black)),
          if (label.isNotEmpty) pw.SizedBox(width: 12),
          pw.Text(isLoss ? '- $value' : value,
              style: cs.copyWith(color: color)),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryTable(List instruments,
      Map<String, dynamic> summary, pw.TextStyle hs, pw.TextStyle cs) {
    final headerBg = PdfColor.fromHex('#C0C0C0');
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [
          _cell('Exchange', hs),
          _cell('Script', hs),
          _cell('Total', hs),
          _cell('Br', hs),
          _cell('Net', hs)
        ],
      ),
    ];

    for (final i in instruments) {
      final pnl = (i['pnl'] as num?)?.toDouble() ?? 0;
      final br = (i['brokerage'] as num?)?.toDouble() ?? 0;
      final net = (i['net_pnl'] as num?)?.toDouble() ?? 0;
      rows.add(pw.TableRow(children: [
        _cell(i['exchange'] ?? '', cs),
        _cell(i['display_name'] ?? i['tradingsymbol'] ?? '', cs),
        _cell('${pnl < 0 ? '- ' : ''}${_fmt.format(pnl.abs())}', cs),
        _cell(_fmt.format(br), cs),
        _cell('${net < 0 ? '- ' : ''}${_fmt.format(net.abs())}', cs),
      ]));
    }

    final totalPnl = (summary['total_pnl'] as num?)?.toDouble() ?? 0;
    final totalBr = (summary['total_brokerage'] as num?)?.toDouble() ?? 0;
    final netPnl = (summary['net_pnl'] as num?)?.toDouble() ?? 0;

    rows.add(pw.TableRow(
      decoration:
          pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
      children: [
        _cell('Total', hs),
        _cell('', cs),
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

  static pw.Widget _buildCarryForwardTable(
      List carryForward, pw.TextStyle hs, pw.TextStyle cs) {
    final headerBg = PdfColor.fromHex('#C0C0C0');
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: [
          _cell('Exchange', hs),
          _cell('Script', hs),
          _cell('Type', hs),
          _cell('Quantity', hs),
          _cell('Price', hs)
        ],
      ),
    ];

    for (final cf in carryForward) {
      final isBuy = cf['type'] == 'Buy';
      rows.add(pw.TableRow(children: [
        _cell(cf['exchange'] ?? '',
            cs.copyWith(color: isBuy ? PdfColors.blue : PdfColors.red)),
        _cell(cf['display_name'] ?? cf['tradingsymbol'] ?? '',
            cs.copyWith(color: isBuy ? PdfColors.blue : PdfColors.red)),
        _cell(cf['type'] ?? '',
            cs.copyWith(color: isBuy ? PdfColors.blue : PdfColors.red)),
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

  // ===================== LIVE BILL (Live M2M) =====================
  //
  // Reference (GM Global "Live Bill") layout — identical to the web portal's
  // bill (apex-web-portal src/lib/pdf.ts buildLiveM2mDoc): brand on top; a
  // ruled "Live Bill | 28 September-03 October | From … To …" band; boxed
  // "(username) name"; one boxed table per script headed "NIFTY 29SEP2026"
  // with Date Time / Type / Lot / Buy Qty / Sell Qty / Rate / Net Rate /
  // Net Amount; a grey "Script Wise total:" row; then Total Brokerage + Final
  // Bill Amt and Buy/Sell Turnover boxes.
  //   BF   — position carried in from last week (report `bf`, bill=1),
  //          counted in the qty totals;
  //   LIVE — the open position closed on paper at the live price on the
  //          OPPOSITE side (reports_view enrichment), not in the qty totals
  //          or turnover, its unrealised P&L in the script total;
  //   other rows — real fills, Type = order label (NORMAL/LIMIT/ADMIN/…).
  // Broker Brokerage is intentionally not shown.

  static final _billAmt = NumberFormat('#,##0.00', 'en_US');
  static final _billRate = NumberFormat('#,##0.0000', 'en_US');
  static final _billQty = NumberFormat('0.##', 'en_US');
  static final _billDateTime = DateFormat('dd-MM-yyyy HH:mm:ss');
  static final _billDate = DateFormat('dd-MM-yyyy');
  static final _billPeriodDay = DateFormat('dd MMMM');
  static const _billBlue = PdfColor.fromInt(0xFF0C51C4);
  static const _billRed = PdfColor.fromInt(0xFFBF2114);
  static const _billGrey = PdfColor.fromInt(0xFFABABAB);
  static const _billLine = pw.BorderSide(width: 0.8);
  static const _billColumns = [
    'Date Time', 'Type', 'Lot', 'Buy Qty', 'Sell Qty', 'Rate', 'Net Rate', 'Net Amount'
  ];
  static const _billColFlex = [35.0, 19.0, 16.0, 17.0, 17.0, 26.0, 27.0, 31.0];

  static String _billMoney(double n) =>
      _billAmt.format(n.abs() < 0.005 ? 0 : n);

  static pw.Widget _billCell(String text,
      {pw.TextAlign align = pw.TextAlign.right, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: color ?? PdfColors.black)),
    );
  }

  static pw.TextAlign _billAlign(int col) => col == 0
      ? pw.TextAlign.left
      : col == 1
          ? pw.TextAlign.center
          : pw.TextAlign.right;

  static pw.Widget _billFooterBox(
      String left, String rightLabel, String rightValue, PdfColor valueColor) {
    final style = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(left, style: style),
          pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: rightLabel, style: style),
              pw.TextSpan(
                  text: rightValue, style: style.copyWith(color: valueColor)),
            ]),
          ),
        ],
      ),
    );
  }

  static pw.Document generateAdvancedReport(Map<String, dynamic> data) {
    final pdf = pw.Document();
    final accountLabel =
        (data['account_label'] ?? data['user_name'] ?? 'Unknown').toString();
    final from = _parseToIST(data['from']);
    final to = _parseToIST(data['to']);
    final instruments = (data['instruments'] as List?) ?? [];
    final bold = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);

    final List<pw.Widget> content = [
      pw.Center(
          child: pw.Text(kIsVolt ? 'Volt' : 'Apex',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 6),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: const pw.BoxDecoration(
            border: pw.Border(top: _billLine, bottom: _billLine)),
        child: pw.Row(children: [
          pw.Expanded(flex: 2, child: pw.Text('Live Bill', style: bold)),
          pw.Expanded(
              flex: 4,
              child: pw.Text(
                  '${_billPeriodDay.format(from)}-${_billPeriodDay.format(to)}',
                  style: bold)),
          pw.Expanded(
              flex: 4,
              child: pw.Text(
                  'From ${_billDate.format(from)} To ${_billDate.format(to)}',
                  textAlign: pw.TextAlign.right,
                  style: bold)),
        ]),
      ),
      pw.SizedBox(height: 4),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
        child: pw.Text(accountLabel, style: bold),
      ),
    ];

    double grandBrokerage = 0;
    double grandNet = 0;
    double buyTurnover = 0;
    double sellTurnover = 0;

    for (final instr in instruments) {
      final title = (instr['bill_name'] ??
              instr['display_name'] ??
              instr['tradingsymbol'] ??
              '')
          .toString();
      final lotSize = (instr['lot_size'] as num?)?.toDouble();
      final pnl = (instr['pnl'] as num?)?.toDouble() ?? 0;
      final brokerage = (instr['brokerage'] as num?)?.toDouble() ?? 0;
      final netPnl = (instr['net_pnl'] as num?)?.toDouble() ?? (pnl - brokerage);
      grandBrokerage += brokerage;
      grandNet += netPnl;

      // (kind, time, type, isBuy, qty, rate, brokerage)
      final rows = <({
        String kind,
        String time,
        String type,
        bool isBuy,
        double qty,
        double rate,
        double br
      })>[];
      for (final bf in (instr['bf'] as List?) ?? []) {
        rows.add((
          kind: 'BF',
          time: bf['date'] == null
              ? ''
              : _billDateTime.format(_parseToIST(bf['date'])),
          type: 'BF',
          isBuy: bf['side'] == 'BUY',
          qty: (bf['qty'] as num?)?.toDouble() ?? 0,
          rate: (bf['rate'] as num?)?.toDouble() ?? 0,
          br: 0,
        ));
      }
      for (final t in (instr['all_trades'] as List?) ?? []) {
        final type = (t['type'] ?? '').toString();
        final bQty = (t['buy_qty'] as num?)?.toDouble() ?? 0;
        final sQty = (t['sell_qty'] as num?)?.toDouble() ?? 0;
        final rate = (t['rate'] as num?)?.toDouble() ?? 0;
        final isLive = type == 'LIVE' || type == 'EXPIRED' || type == 'CLOSED';
        if (isLive) {
          rows.add((
            kind: 'LIVE',
            time: '',
            type: type,
            isBuy: bQty > 0,
            qty: bQty > 0 ? bQty : sQty,
            rate: rate,
            br: 0,
          ));
        } else {
          final isBuy = type == 'BUY' || (type != 'SELL' && bQty > 0);
          final label = (t['order_type_label'] ?? '').toString();
          // A settlement re-open inside the window (multi-week bill) comes
          // as label 'BF' — a carry-in, not a trade: no turnover.
          rows.add((
            kind: label == 'BF' ? 'BF' : 'TRADE',
            time: _billDateTime.format(_parseToIST(t['date'])),
            type: label.isNotEmpty ? label : (isBuy ? 'Buy' : 'Sell'),
            isBuy: isBuy,
            qty: isBuy ? bQty : sQty,
            rate: rate,
            br: (t['brokerage'] as num?)?.toDouble() ?? 0,
          ));
        }
      }

      double totalBuyQty = 0;
      double totalSellQty = 0;
      final tableRows = <pw.TableRow>[
        pw.TableRow(children: [
          for (int c = 0; c < _billColumns.length; c++)
            _billCell(_billColumns[c], align: _billAlign(c)),
        ]),
      ];
      for (final r in rows) {
        if (r.kind != 'LIVE') {
          if (r.isBuy) {
            totalBuyQty += r.qty;
          } else {
            totalSellQty += r.qty;
          }
        }
        if (r.kind == 'TRADE') {
          if (r.isBuy) {
            buyTurnover += r.rate * r.qty;
          } else {
            sellTurnover += r.rate * r.qty;
          }
        }
        // Net Rate = Rate adjusted per unit by this row's brokerage (against
        // the trader); Net Amount = Net Rate × qty, + buy / − sell.
        final perUnit = r.qty > 0 ? r.br / r.qty : 0.0;
        final netRate = r.isBuy ? r.rate + perUnit : r.rate - perUnit;
        final netAmount = r.isBuy ? netRate * r.qty : -(netRate * r.qty);
        final unused = r.kind == 'LIVE' ? '' : '-';
        tableRows.add(pw.TableRow(children: [
          _billCell(r.time, align: pw.TextAlign.left),
          _billCell(r.type, align: pw.TextAlign.center),
          _billCell(lotSize != null && lotSize > 0
              ? _billRate.format(r.qty / lotSize)
              : '-'),
          _billCell(r.isBuy ? _billQty.format(r.qty) : unused,
              color: r.isBuy ? _billBlue : null),
          _billCell(r.isBuy ? unused : _billQty.format(r.qty), color: _billRed),
          _billCell(_billRate.format(r.rate)),
          _billCell(_billRate.format(netRate)),
          _billCell(_billMoney(netAmount),
              color: netAmount >= 0 ? _billBlue : _billRed),
        ]));
      }
      tableRows.add(pw.TableRow(children: [
        _billCell('Script Wise total:',
            align: pw.TextAlign.left, color: _billGrey),
        _billCell('', color: _billGrey),
        _billCell('', color: _billGrey),
        _billCell(_billQty.format(totalBuyQty), color: _billGrey),
        _billCell(_billQty.format(totalSellQty), color: _billGrey),
        _billCell(_billMoney(pnl), color: _billGrey),
        _billCell(_billMoney(brokerage), color: _billGrey),
        _billCell(_billMoney(netPnl), color: _billGrey),
      ]));

      content.add(pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        decoration: const pw.BoxDecoration(
            border: pw.Border(
                left: _billLine, right: _billLine, bottom: _billLine)),
        child: pw.Text(title, textAlign: pw.TextAlign.center, style: bold),
      ));
      content.add(pw.Table(
        border: const pw.TableBorder(
            left: _billLine, right: _billLine, bottom: _billLine),
        columnWidths: {
          for (int c = 0; c < _billColFlex.length; c++)
            c: pw.FlexColumnWidth(_billColFlex[c]),
        },
        children: tableRows,
      ));
    }

    if (instruments.isEmpty) {
      content.add(pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text('No trades or open positions in this period.',
            style: const pw.TextStyle(fontSize: 8.5)),
      ));
    }

    content.add(pw.SizedBox(height: 10));
    content.add(_billFooterBox(
      'Total Brokerage: ${_billMoney(grandBrokerage)}',
      'Final Bill Amt :  ',
      _billMoney(grandNet),
      grandNet >= 0 ? _billBlue : _billRed,
    ));
    content.add(pw.SizedBox(height: 6));
    content.add(_billFooterBox(
      'Buy Turnover: ${_billMoney(buyTurnover)}',
      'Sell Turnover: ',
      _billMoney(sellTurnover),
      PdfColors.black,
    ));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => content,
      ),
    );

    return pdf;
  }
}
