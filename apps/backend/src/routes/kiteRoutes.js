const express = require('express');
const router = express.Router();
const { authenticateAny, authenticateAdmin } = require('../middlewares/auth');
const { requireAdminPermission } = require('../middlewares/requireAdminPermission');
const {
  // Authentication
  initiateLogin,
  handleCallback,
  checkAuthStatus,
  getDetailedAuthStatus,
  triggerAutoLogin,
  logout,
  
  // Instruments
  fetchInstruments,
  getInstrumentsInfo,
  searchInstruments,
  smartSearchInstruments,
  browseInstruments,
  getSearchCategories,
  
  // Market Quotes
  fetchQuotes,
  getLatestQuotes,
  getLTPByToken,
  
  // Option Chain & Market Depth
  getOptionChain,
  getMarketDepth,
  
  // Historical Data
  getHistoricalData,
  
  // Profile
  getProfile
} = require('../controllers/kiteController');

// ==================== AUTHENTICATION ROUTES (PUBLIC) ====================

// Initiate login (redirects to Kite)
router.get('/login', initiateLogin);

// Handle callback from Kite
router.get('/callback', handleCallback);

// AccessToken represents the single shared platform-wide Zerodha broker
// connection (KiteConfig.js's AccessToken.deleteMany({}) + create is a
// singleton pattern, not per-user) — status/auto-login/logout/instrument-sync
// are all broker-administration actions, not something any logged-in user
// or master has a legitimate reason to call. Previously these five sat
// behind `authenticateAny` (auth-status/auth/status/auto-login were fully
// PUBLIC, no auth at all) — any authenticated user could trigger a forced
// re-login or wipe the platform's live broker session with `DELETE
// /logout`, and an unauthenticated client could hit the status/auto-login
// endpoints directly. Confirmed unused by both frontends (grep found no
// caller in apex-web-portal or the Flutter app), so restricting to admin
// is a safe, no-op change for every current UI.

// admin-only above was previously ungated by any permission key — any
// regular Admin (not just ones granted broker-management authority) could
// wipe or force-relogin the platform's single shared broker session, or
// bulk-rewrite the instrument master. INSTRUMENT_MANAGE is the closest
// existing key (fetchInstruments IS instrument management; the
// auth-status/auto-login/logout ones control the session that pipeline
// depends on) — reused rather than inventing a new key for this pass.

// Check auth status (simple)
router.get('/auth-status', authenticateAdmin, requireAdminPermission('INSTRUMENT_MANAGE'), checkAuthStatus);

// Get detailed auth status
router.get('/auth/status', authenticateAdmin, requireAdminPermission('INSTRUMENT_MANAGE'), getDetailedAuthStatus);

// Trigger automated login
router.post('/auth/auto-login', authenticateAdmin, requireAdminPermission('INSTRUMENT_MANAGE'), triggerAutoLogin);

// ==================== PROTECTED ROUTES (REQUIRE AUTHENTICATION) ====================

// Apply authentication middleware to all routes below
router.use(authenticateAny);

// Logout — broker-administration action, admin only (see note above).
router.delete('/logout', authenticateAdmin, requireAdminPermission('INSTRUMENT_MANAGE'), logout);

// ==================== INSTRUMENT ROUTES ====================

// Fetch and store instruments — bulk broker-API-hitting, DB-rewriting
// maintenance operation; admin only (see note above).
router.post('/instruments/fetch', authenticateAdmin, requireAdminPermission('INSTRUMENT_MANAGE'), fetchInstruments);

// Get instruments info
router.get('/instruments/info', getInstrumentsInfo);

// Search instruments (legacy)
router.get('/instruments/search', searchInstruments);

// Smart search instruments (new - with fuzzy matching and grouping)
router.get('/instruments/smart-search', smartSearchInstruments);

// Browse all instruments in a category (no search query)
router.get('/instruments/browse', browseInstruments);

// Get search categories
router.get('/instruments/categories', getSearchCategories);

// ==================== MARKET QUOTE ROUTES ====================

// Fetch quotes from Kite API
router.post('/quotes/fetch', fetchQuotes);

// Get latest quotes from database
router.get('/quotes/latest', getLatestQuotes);

// Get LTP by instrument token
router.get('/quotes/ltp/:instrumentToken', getLTPByToken);

// Get option chain for an instrument
router.get('/option-chain/:tradingSymbol', getOptionChain);

// Get market depth for an instrument
router.get('/market-depth/:instrumentToken', getMarketDepth);

// Get historical candle data
router.get('/historical/:instrumentToken/:interval', getHistoricalData);

// ==================== PROFILE ROUTES ====================

// Get user profile
router.get('/profile', getProfile);

module.exports = router;
