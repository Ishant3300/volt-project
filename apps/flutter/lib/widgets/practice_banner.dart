import 'package:flutter/material.dart';
import '../config/practice_session.dart';
import '../utils/contants.dart';

/// VELO (3 Nov 2026): the practice banner is always on the login and
/// sign-up screens, before anyone logs in. After a practice (email) login
/// main.dart shows it on every screen; after a real user-ID login it is gone
/// everywhere. Volt is unchanged (no banner on its login screen).
class LoginPracticeBannerWrap extends StatelessWidget {
  const LoginPracticeBannerWrap({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsVelo) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: PracticeSession.active,
      builder: (context, practice, _) {
        // Practice mode on → main.dart's banner is already on top.
        if (practice) return child;
        return Column(
          children: [
            const PracticeBanner(),
            Expanded(
              child: MediaQuery.removePadding(
                  context: context, removeTop: true, child: child),
            ),
          ],
        );
      },
    );
  }
}

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
