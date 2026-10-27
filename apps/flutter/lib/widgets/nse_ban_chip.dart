import 'package:flutter/material.dart';
import '../utils/contants.dart';

/// Small red "NSE BAN" tag for a script under NSE F&O ban.
class NseBanChip extends StatelessWidget {
  const NseBanChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: kColorSell.withValues(alpha: 0.1),
        border: Border.all(color: kColorSell.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text('NSE BAN',
          style: TextStyle(color: kColorSell, fontSize: 9, fontFamily: kFontFamily, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
  }
}
