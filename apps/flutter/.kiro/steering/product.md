# Stocker — Product Overview

Stocker is a stock trading and portfolio management platform built for the Indian stock market. It integrates with Zerodha's Kite Connect API for real-time market data, instrument search, option chains, and market depth.

The system has two user roles:
- **Admin**: Manages users, masters, servers, brokerage settings, trade margins, and platform configuration.
- **User**: Views watchlists with live prices, places orders, tracks trade history, and manages their portfolio.

Key capabilities:
- Real-time price streaming via WebSocket
- Watchlist management with live price updates
- Option chain and market depth views
- Order placement (buy/sell) with stop-loss and trigger prices
- Admin dashboard for user management, credit/balance tracking, and settlement reports
- Automated Kite login via Puppeteer for unattended server starts
- Instrument data fetched daily from Kite and stored in MongoDB (FUT, CE, PE, EQ types)

The backend runs as a Node.js/Express API server. The frontend is a cross-platform Flutter app (mobile + web).
