import 'package:flutter/material.dart';
import '../models/master.dart';
import '../utils/contants.dart';

class MasterCard extends StatelessWidget {
  final Master master;
  final VoidCallback? onTap;

  const MasterCard({
    super.key,
    required this.master,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final balance = master.equity.toStringAsFixed(2);
    final credit = master.credits.toStringAsFixed(2);
    final plShare = '${master.pnlSharing.toStringAsFixed(1)}%';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    master.username,
                    style: TextStyle(
                      color: kColorTextPrimary,
                      fontSize: kFontSizeName,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightName,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: master.activeStatus
                        ? kColorBuy
                        : kColorSell,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    master.activeStatus ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: kFontSizeCaption,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightRegular,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              master.name,
              style: TextStyle(
                color: const Color(0xFF666666),
                fontSize: kFontSizeSubtitle,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightRegular,
              ),
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'BALANCE: $balance',
                  style: TextStyle(
                    color: const Color(0xFF999999),
                    fontSize: kFontSizeSubtitle,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightRegular,
                  ),
                ),
                Text(
                  'CREDIT: $credit',
                  style: TextStyle(
                    color: const Color(0xFF999999),
                    fontSize: kFontSizeSubtitle,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightRegular,
                  ),
                ),
                Text(
                  'PL SHARE: $plShare',
                  style: TextStyle(
                    color: const Color(0xFF999999),
                    fontSize: kFontSizeSubtitle,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightRegular,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
