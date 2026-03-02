# Project Structure

## Directory Organization

```
stocker/lib/
├── main.dart              # App entry point, provider setup
├── initial_sheet.dart     # Initial screen/splash
├── home_page.dart         # Main home screen
├── models/                # Data models
├── pages/                 # Full-screen pages
├── views/                 # Reusable view components
├── widgets/               # Small reusable widgets
├── providers/             # State management (Provider pattern)
├── services/              # Business logic and API communication
└── utils/                 # Constants and utilities
```

## Architecture Pattern

The app follows a layered architecture with clear separation of concerns:

1. **Models** (`models/`): Plain Dart classes representing data structures
   - User, Trade, Position, WatchlistItem, KiteInstrument, etc.

2. **Services** (`services/`): Business logic and external communication
   - `api_service.dart`: Base HTTP client
   - `auth_service.dart`: Authentication logic
   - `kite_service.dart`: Kite API integration
   - `live_price_service.dart`: WebSocket price updates
   - `watchlist_service.dart`, `user_service.dart`, etc.

3. **Providers** (`providers/`): State management using Provider pattern
   - `watchlist_provider.dart`: Manages watchlist state

4. **Pages** (`pages/`): Full-screen routes
   - LoginPage, WatchlistPage, HistoryPage, OrdersPage, etc.

5. **Views** (`views/`): Complex reusable UI components
   - Settings views, detail views, bottom sheets, etc.

6. **Widgets** (`widgets/`): Small reusable UI components
   - Cards, custom controls, etc.

## Key Conventions

- Use `const` constructors where possible for performance
- Services are provided via Provider/ProxyProvider in main.dart
- Navigation uses named routes and NavigationService
- Logging uses `dart:developer` log function with emoji prefixes
- Secure data (tokens) stored via flutter_secure_storage
- File naming: snake_case for all Dart files
- Class naming: PascalCase
