import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../config/practice_session.dart';

// White-label branding (app name, logo, brand colours). Re-exported here so that
// every file already importing this constants file picks up the brand tokens
// without needing an extra import. Values are resolved at compile time — see
// lib/config/app_brand.dart and build with --dart-define=BRAND=volt for Volt.
export '../config/app_brand.dart';

// Android emulator uses 10.0.2.2 to reach host machine; iOS simulator uses localhost
// final String backendUrl = Platform.isAndroid ? "http://10.0.2.2:3000" : "http://127.0.0.1:3000";
// final String backendUrl =
//     "http://192.168.1.6:3000"; // Physical device (use your LAN IP)
// Production server — the live backend, or the separate practice (paper
// trading) backend while a practice account is active (PracticeSession).
String get backendUrl => PracticeSession.baseUrl;

/// Always the live server (APK downloads / version check).
const String kLiveBackendUrl = PracticeSession.liveUrl;

const bool kLogLivePrices = false;
const bool kLogWebSockets = false;
const bool kLogTokenWarnings = false;

// ─── Text / Action Colors ───────────────────────────────────────────────────
// Sampled directly from the reference app's History screen (instrument
// names, user tags, timestamps, BUY/SELL labels, Deals badges) — not brand
// colors (those stay in app_brand.dart's kBrandPrimary etc., per-flavor and
// untouched here). These are plain shared UI tokens for wherever a screen
// needs "the dark text" / "the muted text" / "the buy blue" / "the sell red"
// look, so a redesign doesn't have to keep re-typing the same hex.
const Color kColorTextPrimary = Color(0xFF1F2429); // headings, instrument names, user tags
const Color kColorTextMuted = Color(0xFF8C939D); // timestamps, inactive tabs/nav items
const Color kColorBuy = Color(0xFF2E7BE5); // BUY labels, buy prices, active-state accents
const Color kColorSell = Color(0xFFC94A4A); // SELL labels, sell prices, loss figures
const Color kColorBuyBadgeBg = Color(0xFFE8F1FD); // light tint behind a BUY badge
const Color kColorSellBadgeBg = Color(0xFFFCEAE9); // light tint behind a SELL badge
const Color kColorLossBadgeBg = Color(0xFFFDE8E8); // light tint behind a "Deals: -…" loss pill

// One-tap "Reset Password" (username_view.dart / web's PasswordResetPage.tsx)
// sets a user's/master's password to this fixed value instead of requiring
// the admin/master to type one every time. change_pass_on_first_login isn't
// touched by this — it only applies at account creation — so whether the
// account is forced to change it on next login depends on however that flag
// was already set.
const String kDefaultResetPassword = '123456';

// ─── Font Sizes ─────────────────────────────────────────────────────────────

// Font Weights
// Bumped one notch app-wide (previously w300/w300/w400/w400 — visibly thin,
// and Bold/SemiBold were indistinguishable from each other at the same
// w400). Every screen sharing these four constants gets the bolder look in
// one place — Watchlist is exempt, it already uses its own literal weights
// from the earlier redesign rather than these constants.
const FontWeight kFontWeightRegular =
    FontWeight.w400; // Body text, hints, metadata, labels across all pages
const FontWeight kFontWeightMedium =
    FontWeight.w400; // Secondary text, search fields, menu items, tab labels
const FontWeight kFontWeightSemiBold =
    FontWeight.w600; // Titles, card names, buttons, badges, option names
const FontWeight kFontWeightBold =
    FontWeight.w600; // Page titles, P&L values, emphasis text
// Distinct from kFontWeightSemiBold — pill/tag badges (BUY/SELL, ADMIN,
// DELETE, Closed…) want a visibly heavier 700 per the typography spec, while
// titles/prices sharing kFontSizeTradeSymbol-style constants stay at 600.
const FontWeight kFontWeightBadge = FontWeight.w700;

// Universal Name Style (option names, usernames, master names, instrument names — all screens)
const double kFontSizeName =
    12.0; // Profile names, master names, user names, instrument names in all cards/lists
const FontWeight kFontWeightName =
    FontWeight.w600; // Weight for all names across the app

// Display / Splash
const double kFontSizeDisplay = 32.0;
const double kFontSizePageTitle = 24.0;
const double kFontSizeViewTitle = 18.0;
const double kFontSizeLoginTitle = 32.0;

// Section & Card Headers
const double kFontSizeSectionHeader = 16.0;
const double kFontSizeButtonText = 15.0;

// Body Text
const double kFontSizeBody = 13.0; // title, orders page tile, top segment tabs
const double kFontSizeBodySmall =
    12.0; // bottom sheets, trade margin, group quantity, script quantity
const double kFontSizeSubtitle = 10.0;

// Navigation
const double kFontSizeNavLabel = 11.0; // Nav text
const double kFontSizeNavIcon = 14.0; // Nav icons

// Small / Captions
const double kFontSizeCaption = 11.0; // all sub text under cards in all pages
const double kFontSizeBadge = 10.0; // badges on account

// Price Data
const double kFontSizePriceMain = 13.0; // All primary prices
const double kFontSizePriceSecondary = 11.0; // All secondary prices (low, high)
const double kFontSizeInstrumentName = 12.0; // Instrument names

// Trade Card / Position Card (Watchlist, Orders, History, Username View)
const double kFontSizeTradeSymbol =
    14.0; // Instrument name in trade/position cards
const double kFontSizeTradePrice = 14.0; // Price on right side of trade cards
const double kFontSizeTradeBadge = 12.0; // BUY/SELL/PENDING badges
const double kFontSizeTradeMetadata = 10.0; // Volume, time, username metadata
const double kFontSizePositionSymbol =
    11.5; // Symbol in position cards // user's view in orders page
const double kFontSizePositionDetail =
    11.0; // Exchange, avg price, side badge text
const double kFontSizePositionPnl = 14.0; // Floating P&L value

// Bottom Sheets
const double kFontSizeSheetTitle = 16.0;
const double kFontSizeSheetLabel = 12.0;
const double kFontSizeSheetBody = 14.0;
const double kFontSizeSheetHint = 13.0;

// Icon Sizes
const double kIconSizeSmall = 14.0;
const double kIconSizeDefault = 16.0;
const double kIconSizeMedium = 24.0;
const double kIconSizeLarge = 24.0;
const double kIconSizeXLarge = 32.0;
const double kIconSizeProfileMenu = 28.0;

// Menu Item Layout (Profile, Reports, Settings, Admin Settings — shared)
//
// The icon-tile size/shape and row height are brand-specific: see
// `kMenuTileSize` / `kMenuTileIconSize` / `kMenuRowVerticalPadding` in
// lib/config/app_brand.dart. Don't rebuild menu rows by hand — use
// `BrandMenuRow` (lib/widgets/brand_menu_row.dart) so both brands stay correct.
const double kFontSizeMenuItem = 15.0;
const double kMenuChevronSize = 24.0;

// ─── SVG Icon Paths ─────────────────────────────────────────────────────────
// Bottom Navigation
const String kIconWatchlist = 'lib/icons/watchlist_icon.svg';
const String kIconOrders = 'lib/icons/orders_icon.svg';
const String kIconHistory = 'lib/icons/history_icon.svg';
const String kIconProfile = 'lib/icons/profile_icon.svg';
const String kIconEdit = 'lib/icons/edit_icon.svg';

// Profile Page Menu
const String kIconAccountDetails =
    'lib/icons/profile_page_icons/account_details.svg';
const String kIconAdminSettings =
    'lib/icons/profile_page_icons/admin_settings.svg';
const String kIconDeleteAccount =
    'lib/icons/profile_page_icons/delete_account.svg';
const String kIconInviteFriends =
    'lib/icons/profile_page_icons/invite_friends.svg';
const String kIconLoginHistory =
    'lib/icons/profile_page_icons/login_history.svg';
const String kIconLogout = 'lib/icons/profile_page_icons/logout.svg';
const String kIconMasterUserMgmt =
    'lib/icons/profile_page_icons/master_and_user_management.svg';
const String kIconReports = 'lib/icons/profile_page_icons/reports.svg';
const String kIconSettings = 'lib/icons/profile_page_icons/settings.svg';

// Reports View
const String kIconAccountSummary =
    'lib/icons/reports_view_icons/account_summary.svg';
const String kIconDeletedTrades =
    'lib/icons/reports_view_icons/deleted_trades.svg';
const String kIconGeneratePdf = 'lib/icons/reports_view_icons/generate_pdf.svg';
const String kIconIntradayHistory =
    'lib/icons/reports_view_icons/intraday_history.svg';
const String kIconProfitAndLoss =
    'lib/icons/reports_view_icons/profit_and_loss.svg';
const String kIconRejectionLogHistory =
    'lib/icons/reports_view_icons/rejection_log_history.svg';
const String kIconScriptQtyDetails =
    'lib/icons/reports_view_icons/script_qty_details.svg';
const String kIconUserwisePosition =
    'lib/icons/reports_view_icons/userwise_open_position.svg';
const String kIconWeeklyAdminReport =
    'lib/icons/reports_view_icons/weekly_admin_report.svg';

// Settings View
const String kIconChangePassword =
    'lib/icons/settings_view_icons/change_password.svg';
const String kIconMarketHours =
    'lib/icons/settings_view_icons/market_hours.svg';
const String kIconNotifications =
    'lib/icons/settings_view_icons/notifications.svg';
const String kIconPrivacyPolicy =
    'lib/icons/settings_view_icons/privacy_policy.svg';
const String kIconSetQuantityValues =
    'lib/icons/settings_view_icons/set_quantity_values.svg';
const String kIconTermsOfUse = 'lib/icons/settings_view_icons/terms_of_use.svg';

// Username View (User/Master management)
const String kIconBrokerageSettings =
    'lib/icons/username_view_icons/brokerage_settings.svg';
const String kIconCreditDebit =
    'lib/icons/username_view_icons/credit_debit.svg';
const String kIconGeneratePdfUser =
    'lib/icons/username_view_icons/generate_pdf.svg';
const String kIconGroupQuantity =
    'lib/icons/username_view_icons/group_quantity_settings.svg';
const String kIconIntradaySquareoff =
    'lib/icons/username_view_icons/intraday_squareoff.svg';
const String kIconMarginSquareoff =
    'lib/icons/username_view_icons/margin_squareoff_settings.svg';
const String kIconRejectionLog =
    'lib/icons/username_view_icons/rejection_log.svg';
const String kIconScriptQuantity =
    'lib/icons/username_view_icons/script_quantity_settings.svg';
const String kIconSettlementReport =
    'lib/icons/username_view_icons/settlement_report.svg';
const String kIconSharingDetails =
    'lib/icons/username_view_icons/sharing_details.svg';
const String kIconTradeMargin =
    'lib/icons/username_view_icons/trade_margin_settings.svg';
const String kIconTradeWallet =
    'lib/icons/username_view_icons/trade_margin_settings.svg';
