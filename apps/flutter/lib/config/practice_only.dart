/// Practice-only build (the iOS App Store app "VOLT - Learn & Practice").
///
/// Build with `--dart-define=PRACTICE_ONLY=true` (codemagic.yaml, iOS only).
/// The app then signs in to the practice (paper trading) backend only, and
/// the admin / master screens, the live-server login and the Android APK
/// updater are not compiled in at all: every use sits behind this const, so
/// the compiler drops that code from the binary (Apple rejected 1.0.51 (55)
/// under guideline 2.5.19 for containing them, 23 Oct 2026).
///
/// Off by default — the Android APKs and every other build are unchanged.
const bool kPracticeOnly = bool.fromEnvironment('PRACTICE_ONLY');
