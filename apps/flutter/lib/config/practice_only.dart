/// Practice-server-only build: the iOS trading simulator (VELO, new Apple
/// account). Build with `--dart-define=PRACTICE_ONLY=true` (codemagic.yaml,
/// iOS workflows only).
///
/// Every screen and role is included (client, master, admin), but the app
/// talks to the practice (simulation) backend only: the live server address,
/// the live-server picker and the Android APK updater are not compiled in
/// (they sit behind this const, so the compiler drops them). Apple rejected
/// 1.0.51 (55) under guideline 2.5.19 for containing a hidden live login, and
/// the codemagic safety gate fails any build where that code is present.
/// Live trading on iOS may only come later as a reviewed update, with the
/// licence.
///
/// Off by default — the Android APKs and every other build are unchanged.
const bool kPracticeOnly = bool.fromEnvironment('PRACTICE_ONLY');
