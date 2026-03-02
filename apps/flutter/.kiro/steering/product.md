# Product Overview

Stocker is a Flutter-based stock trading management application that integrates with Kite (Zerodha's trading platform) for real-time market data and trading operations.

## Core Functionality

- User authentication and authorization with JWT tokens
- Real-time stock price monitoring via WebSocket connections
- Watchlist management for tracking instruments
- Trade execution and order management
- Position tracking (intraday and margin trades)
- Market depth and option chain analysis
- Admin panel for user and master account management
- Trade history and profit/loss reporting
- Brokerage and quantity settings configuration

## User Roles

- Regular users: Execute trades, manage watchlists, view positions
- Admin users: Manage users, configure settings, view reports, control market hours

## Backend Integration

The app communicates with a backend API (default: http://127.0.0.1:3000) for authentication, trade management, and data persistence. Real-time market data is fetched via Kite API integration.
