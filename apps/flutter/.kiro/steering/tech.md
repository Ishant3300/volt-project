# Tech Stack & Build Info

## Frontend — Flutter (`stocker/`)

- **Dart SDK**: ^3.6.0
- **State management**: Provider
- **HTTP**: http package
- **Auth storage**: flutter_secure_storage
- **WebSocket**: web_socket_channel
- **UI**: Material Design, Google Fonts (Inter), flutter_svg, flutter_slidable, animated_flip_counter
- **Charts**: interactive_chart
- **PDF reports**: pdf + printing packages
- **Calendar**: table_calendar
- **Firebase**: firebase_core, firebase_messaging
- **Notifications**: flutter_local_notifications
- **Audio**: audioplayers (trade bell sound)
- **Linting**: flutter_lints
- **App icons**: flutter_launcher_icons

## Backend — Node.js (`stocker-backend-node/`)

- **Framework**: Express
- **Database**: MongoDB via Mongoose
- **Auth**: JWT (jsonwebtoken) + bcryptjs
- **Cache/Queue**: Redis (ioredis) + BullMQ
- **Kite API**: kiteconnect SDK
- **Browser automation**: Puppeteer (+ stealth plugin) for Kite auto-login
- **Push notifications**: Firebase Admin SDK
- **CSV parsing**: csv-parser
- **HTTP client**: axios
- **Scheduling**: node-cron
- **WebSocket server**: ws
- **Testing**: Jest + Supertest
- **Dev**: nodemon

## Infrastructure

- MongoDB (primary database)
- Redis (order book, price queue, caching)
- Firebase (push notifications)
- Zerodha Kite Connect API (market data)

## Common Commands

| Command | Directory | Description |
|---|---|---|
| `npm start` | `stocker-backend-node/` | Start backend |
| `npm run dev` | `stocker-backend-node/` | Start backend with nodemon |
| `npm run fetch-instruments` | `stocker-backend-node/` | Fetch Kite instruments |
| `node scripts/seedAdmin.js` | `stocker-backend-node/` | Seed admin user |
| `node scripts/seedServer.js` | `stocker-backend-node/` | Seed server config |
| `flutter run` | `stocker/` | Run Flutter app |
| `flutter build apk` | `stocker/` | Build release APK |
| `flutter analyze` | `stocker/` | Run Dart analyzer |
| `flutter pub run flutter_launcher_icons` | `stocker/` | Generate app icons |

## Environment Setup

1. Copy `.env.example` to `.env` in `stocker-backend-node/`
2. Required env vars: `PORT`, `MONGO_URI`, `JWT_SECRET`, `REDIS_URL`
3. Backend entry point: `src/index.js`
