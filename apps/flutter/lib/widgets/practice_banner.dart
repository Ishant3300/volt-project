import 'package:flutter/material.dart';
import '../utils/contants.dart';

/// Permanent top banner for practice (paper trading) accounts — shown over
/// every screen by MaterialApp.builder in main.dart while
/// PracticeSession.active is true.
class PracticeBanner extends StatelessWidget {
  const PracticeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF3C7),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: const [
              Icon(Icons.school_outlined, size: 16, color: Color(0xFF92400E)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Practice account · No real money · Prices are simulated (not real market prices) and change every 30 minutes',
                  style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 11.5,
                      height: 1.3,
                      color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
