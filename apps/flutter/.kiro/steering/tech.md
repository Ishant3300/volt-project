# Tech Stack & Build

## Backend (`stocker-backend-node/`)

- **Runtime**: Node.js (CommonJS modules, `require` style)
- **Framework**: Express.js
- **Database**: MongoDB via Mongoose ODM
- **Auth**: JWT (jsonwebtoken) + bcryptjs, no token expiration
- **Real-time**: WebSocket server (ws) for live price streaming
- **External API**: Zerodha Kite Connect SDK (`kiteconnect`) + raw REST calls to `api.kite.trade`
- **Automation**: Puppeteer for automated Kite login
- **Scheduling**: node-cron for periodic tasks
- **Config**: dotenv for environment variables

### Backend Commands

```bash
# Start production server
npm start                    # runs: node src/index.js

# Start dev server with auto-reload
npm run dev                  # runs: nodemon src/index.js

# Fetch instruments from Kite API
npm run fetch-instruments    # runs: node scripts/fetchInstruments.js

# Seed admin user
node scripts/seedAdmin.js

# Seed server data
node scripts/seedServer.js
```

### Environment Variables (`.env`)

Required: `PORT`, `MONGO_URI`, `JWT_SECRET`, `KITE_API_KEY`, `KITE_API_SECRET`

## Frontend (`stocker/`)

- **Framework**: Flutter (Dart SDK ^3.6.0)
- **State Management**: Provider (`provider` ^6.1.2)
- **HTTP**: `http` package for REST calls
- **WebSocket**: `web_socket_channel` for live price streaming
- **Storage**: `flutter_secure_storage` for JWT token persistence
- **Design**: Material Design 3 with Cupertino icons
- **Linting**: `flutter_lints` ^5.0.0

### Frontend Commands

```bash
# Get dependencies
flutter pub get

# Run the app
flutter run

# Build for specific platform
flutter build apk
flutter build ios
flutter build web

# Run tests
flutter test

# Analyze code
flutter analyze
```

### Backend URL Configuration

The backend URL is hardcoded in `stocker/lib/utils/contants.dart`. Update this when switching environments.
