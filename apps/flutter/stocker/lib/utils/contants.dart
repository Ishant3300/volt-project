import 'dart:io' show Platform;
import 'package:flutter/material.dart';

// Android emulator uses 10.0.2.2 to reach host machine; iOS simulator uses localhost
// final String backendUrl = Platform.isAndroid ? "http://10.0.2.2:3000" : "http://127.0.0.1:3000";
final String backendUrl =
    "http://192.168.1.4:3000"; // Physical device (use your LAN IP)
// final String backendUrl = "https://apexlive-api.mynpe.in";       // Production server

const bool kLogLivePrices = false;
const bool kLogWebSockets = false;
const bool kLogTokenWarnings = false;

// ─── Font Sizes ─────────────────────────────────────────────────────────────

// Font Weights
const FontWeight kFontWeightRegular =
    FontWeight.w300; // Body text, hints, metadata, labels across all pages
const FontWeight kFontWeightMedium =
    FontWeight.w300; // Secondary text, search fields, menu items, tab labels
const FontWeight kFontWeightSemiBold =
    FontWeight.w400; // Titles, card names, buttons, badges, option names
const FontWeight kFontWeightBold =
    FontWeight.w400; // Page titles, P&L values, emphasis text

// Universal Name Style (option names, usernames, master names, instrument names — all screens)
const double kFontSizeName =
    12.0; // Profile names, master names, user names, instrument names in all cards/lists
const FontWeight kFontWeightName =
    FontWeight.w400; // Weight for all names across the app

// Display / Splash
const double kFontSizeDisplay = 32.0;
const double kFontSizePageTitle = 24.0;
const double kFontSizeViewTitle = 18.0;
const double kFontSizeLoginTitle = 32.0;

// Section & Card Headers
const double kFontSizeSectionHeader = 16.0;
const double kFontSizeButtonText = 15.0;

// Body Text
const double kFontSizeBody = 12.0; // title, orders page tile
const double kFontSizeBodySmall =
    12.0; // bottom sheets, trade margin, group quantity, script quantity
const double kFontSizeSubtitle = 10.0;

// Navigation
const double kFontSizeNavLabel = 11.0; // Nav text
const double kFontSizeNavIcon = 14.0; // Nav icons

// Small / Captions
const double kFontSizeCaption = 10.0; // all sub text under cards in all pages
const double kFontSizeBadge = 10.0; // badges on account

// Price Data
const double kFontSizePriceMain = 13.0; // All primary prices
const double kFontSizePriceSecondary = 11.0; // All secondary prices (low, high)
const double kFontSizeInstrumentName = 12.0; // Instrument names

// Trade Card / Position Card (Watchlist, Orders, History, Username View)
const double kFontSizeTradeSymbol =
    12.0; // Instrument name in trade/position cards
const double kFontSizeTradePrice = 14.0; // Price on right side of trade cards
const double kFontSizeTradeBadge = 10.0; // BUY/SELL/PENDING badges
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

// Menu Item Layout (Profile, Reports, Settings — shared)
const double kFontSizeMenuItem = 15.0;
const double kMenuIconCircleSize = 32.0;
const double kMenuIconSize = 16.0;
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
