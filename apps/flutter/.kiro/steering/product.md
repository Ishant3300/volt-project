# APEX — "Your Edge in the Market"

APEX is a stock and commodity trading platform consisting of a Flutter mobile app (`stocker/`) and a Node.js backend API (`stocker-backend-node/`).

## Supported Exchanges

- **NSE**: NFO-FUT, NFO-OPT
- **MCX**: MCX-FUT, MCX-OPT
- **GLOBAL**

## Market Data Integration

- Zerodha Kite Connect API for live market data, instrument data, and automated login
- WebSocket-based live price streaming
- Redis + BullMQ for order book and price queue processing
- Cron jobs for scheduled tasks (instrument fetching, metrics collection, etc.)

## Role Hierarchy

Admin → Master → User (role-based access control throughout the platform)

## Core Features

- Real-time watchlists with live price updates
- Trade execution and order management
- Position tracking and P&L reports
- Trade history and settlement reports
- Market depth and option chains
- Brokerage settings and margin management
- Credit/debit transactions
- Multi-account switching (mobile app)
- Firebase push notifications (FCM) for trade alerts
- PDF report generation
