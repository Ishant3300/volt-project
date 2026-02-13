# Project Structure

This is a monorepo with two top-level projects:

```
stocker-backend-node/    # Node.js backend API
stocker/                 # Flutter frontend app
```

## Backend (`stocker-backend-node/src/`)

```
src/
├── index.js                 # Entry point — Express setup, DB connect, Kite auto-login
├── database/
│   └── database.js          # Mongoose connection + index sync
├── controllers/             # Request handlers with business logic
│   ├── authController.js    # User/Admin login & logout
│   ├── adminController.js   # CRUD for users, masters, servers
│   ├── kiteController.js    # Kite API proxy endpoints
│   └── watchlistController.js
├── middlewares/
│   └── auth.js              # JWT auth: authenticateUser, authenticateAdmin, authenticateAny, authenticateOptional
├── models/                  # Mongoose schemas
│   ├── User.js, Admin.js, Master.js, Server.js
│   ├── Order.js, Portfolio.js
│   ├── KiteInstrument.js, KiteConfig.js, KiteAccessToken.js, KiteMarketQuote.js
│   ├── Watchlist.js, QuantityValue.js, LoginActivity.js
│   └── ...
├── routes/                  # Express route definitions (maps to controllers)
├── services/                # External integrations
│   ├── kiteService.js       # Kite REST API (instruments, quotes, tokens)
│   ├── kiteAuthService.js   # Automated Kite login via Puppeteer
│   └── livePriceService.js  # WebSocket server for real-time price streaming
scripts/                     # Utility scripts (seed data, fetch instruments)
test/                        # Manual test scripts
docs/                        # API documentation
```

### Backend Conventions
- Controllers handle request/response and business logic
- Services handle external API integrations
- Models define Mongoose schemas with `toJSON` transforms (`_id` → `id`, `createdAt` → `created_at`)
- All API responses use `{ success, message, data }` format
- Soft deletes via `deleted_at` field (not actual deletion)
- File naming: camelCase (e.g., `authController.js`)

## Frontend (`stocker/lib/`)

```
lib/
├── main.dart                # App entry — MultiProvider setup, MaterialApp
├── home_page.dart           # Bottom nav: Watchlist, Orders, History, Profile
├── initial_sheet.dart       # Startup auth check / routing
├── utils/
│   └── contants.dart        # Backend URL config
├── models/                  # Data classes with fromJson/toJson
│   ├── kite_instrument.dart
│   ├── watchlist_item.dart
│   ├── option_chain.dart
│   └── market_depth.dart
├── services/                # API communication layer
│   ├── api_service.dart     # Base HTTP client (GET/POST/PUT/DELETE) with auto 401 handling
│   ├── auth_service.dart    # Login/logout, token management
│   ├── admin_service.dart   # Admin CRUD operations
│   ├── kite_service.dart    # Kite API proxy (option chain, market depth, search)
│   ├── live_price_service.dart  # WebSocket client for real-time prices
│   ├── watchlist_service.dart
│   ├── user_service.dart
│   ├── navigation_service.dart
│   └── sercure_storage_service.dart  # Note: typo in filename is intentional (existing convention)
├── providers/               # State management (ChangeNotifier)
│   └── watchlist_provider.dart
├── pages/                   # Full-screen pages (top-level navigation targets)
│   ├── watchlist_page.dart, orders_page.dart, history_page.dart, profile_page.dart
│   ├── login_page.dart, instrument_search_page.dart
│   └── trade_detail_sheet.dart, history_filter_sheet.dart
└── views/                   # Reusable views, sub-screens, bottom sheets, and settings panels
    ├── trade_card_view.dart, option_chain_view.dart, market_depth_sheet.dart
    ├── user_management_view.dart, create_user_view.dart, edit_user_view.dart
    ├── settings_view.dart, brokerage_settings_view.dart, ...
    └── ... (40+ view files)
```

### Frontend Conventions
- `pages/` = top-level screens navigated to from the main nav or routes
- `views/` = sub-screens, detail panels, bottom sheets, settings views
- `services/` = each service wraps `ApiService` and handles one domain
- `providers/` = `ChangeNotifier` classes for reactive state via Provider
- `models/` = plain Dart classes with `fromJson`/`toJson` using snake_case keys matching the backend
- File naming: snake_case (e.g., `auth_service.dart`)
- Services receive `ApiService` via constructor injection; token retrieved from `SecureStorageService`
- 401 responses auto-redirect to login via `NavigationService`
