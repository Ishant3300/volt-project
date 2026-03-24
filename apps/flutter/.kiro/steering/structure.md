# Project Structure

Monorepo with two main directories:

## `stocker/` — Flutter Mobile App

```
lib/
├── models/          # Data models (Trade, User, Position, WatchlistItem, etc.) with fromJson/toJson
├── pages/           # Top-level page widgets (login, watchlist, orders, history, profile)
├── views/           # Sub-views and detail screens (admin settings, brokerage, user management, trade cards)
├── widgets/         # Reusable widget components (master_card, user_card)
├── services/        # API communication, auth, live prices, Firebase, trade execution
├── providers/       # Provider state management (user_profile, trade_metrics, watchlist)
├── utils/           # Constants (backend URL, log flags), date formatting, market hours
├── home_page.dart   # Main tab navigation (Watchlist, Orders, History, Profile)
└── initial_sheet.dart  # Splash screen + auth check entry point
assets/              # App icon, SVG logo, trade bell sound
android/, ios/, web/, linux/, macos/, windows/  # Platform-specific code
```

## `stocker-backend-node/` — Node.js Backend API

```
src/
├── index.js         # Express server entry point, route registration, service init
├── controllers/     # Request handlers / business logic (one per domain: trade, auth, admin, master, user, watchlist)
├── services/        # External integrations & background services (Kite API, live prices, Redis, BullMQ, cron, Firebase, margin, metrics)
├── models/          # Mongoose schemas (Trade, User, Master, Admin, Order, KiteInstrument, etc.)
├── routes/          # Express route definitions (auth, admin, user, kite, watchlist, master, trade, server, message)
├── middlewares/     # Auth middleware (authenticateUser, authenticateAdmin, authenticateMaster, authenticateAny, authenticateOptional, authenticateAdminOrMaster)
├── database/        # MongoDB connection setup
├── firebase/        # Firebase service account config
└── config/          # Configuration (log flags)
scripts/             # Utility scripts (seed admin, seed server, fetch instruments, migrations)
tests/ and test/     # Test files
docs/                # Feature documentation
```

## Key Conventions

- **DB collections & model fields**: snake_case
- **API endpoints**: kebab-case
- **JS filenames**: camelCase
- **API response format**: `{ success: bool, message: string, data: object }`
- **Error handling**: All controllers use try-catch
- **Auth**: JWT Bearer tokens, role-based (admin/master/user)
- **Mongoose schemas**: Use timestamps; transform `_id` → `id`, `createdAt` → `created_at`
- **Pagination**: Default 20 items per page
- **Flutter models**: fromJson/toJson factory pattern
- **Flutter architecture**: Services handle API calls, Providers manage state, Pages are top-level screens, Views are sub-screens/detail views
