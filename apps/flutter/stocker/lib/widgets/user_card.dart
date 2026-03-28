import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/contants.dart';

class UserCard extends StatelessWidget {
  final User user;
  final VoidCallback? onTap;

  const UserCard({
    super.key,
    required this.user,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final balance = user.equity.toStringAsFixed(2);
    final credit = user.credits.toStringAsFixed(2);
    final plShare = '${user.pnlSharing.toStringAsFixed(1)}%';

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
                    user.username,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeName,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightName,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: user.status == 'active'
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF3B30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    user.status.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: kFontSizeCaption,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightRegular,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              user.name,
              style: TextStyle(
                color: const Color(0xFF666666),
                fontSize: kFontSizeSubtitle,
                fontFamily: 'Inter',
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
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightRegular,
                  ),
                ),
                Text(
                  'CREDIT: $credit',
                  style: TextStyle(
                    color: const Color(0xFF999999),
                    fontSize: kFontSizeSubtitle,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightRegular,
                  ),
                ),
                Text(
                  'PL SHARE: $plShare',
                  style: TextStyle(
                    color: const Color(0xFF999999),
                    fontSize: kFontSizeSubtitle,
                    fontFamily: 'Inter',
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
