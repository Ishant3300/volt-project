/**
 * Live Price Service
 * Connects to Kite WebSocket for live ticks and broadcasts to Flutter clients via WS
 */

const WebSocket = require('ws');
const jwt = require('jsonwebtoken');
const kiteService = require('./kiteService');
const priceQueueService = require('./priceQueueService');
const syntheticInstrumentService = require('./syntheticInstrumentService');
const KiteInstrument = require('../models/KiteInstrument');
const KiteMarketQuote = require('../models/KiteMarketQuote');
const { LOG_LIVE_TICKS, LOG_WS_BROADCAST } = require('../config/logFlags');
const metricsEngine = require('./metricsEngine');
const SettlementRun = require('../models/SettlementRun');
const { dateRange, isWeekendInIndia } = require('../utils/settlementDates');

class LivePriceService {
  constructor() {
      this.wss = null;           // WebSocket server for Flutter clients
      this.kiteTicker = null;    // Kite WebSocket connection
      this.subscribedTokens = new Set();
      this.clients = new Set();
      // userId -> Set<ws> — O(1) lookup for broadcastToUser instead of a
      // linear scan of every connected client on every call (that scan ran
      // once per affected user per ~50ms metricsEngine debounce cycle).
      this.userClients = new Map();
      this.latestPrices = new Map();

      // Client-facing tick broadcast coalescing/throttle. metricsEngine.onTick
      // and priceQueueService (order matching) still run per-tick, unthrottled
      // — only the WS fan-out to Flutter clients is batched, same reasoning as
      // massiveFuturesFeedService's BROADCAST_THROTTLE_MS. Ticks arrive as
      // Kite message batches (not one-by-one), often faster than clients can
      // usefully render; this caps client-facing broadcast frequency instead
      // of firing a synchronous fan-out to every connected client on every
      // single incoming Kite message.
      this._pendingBroadcastTicks = new Map(); // instrument_token -> latest tick
      this._broadcastFlushTimer = null;
      this.BROADCAST_THROTTLE_MS = 300;
      // Backpressure: a client whose outgoing buffer has grown past this
      // (slow/stalled connection, e.g. a bad mobile network) gets its send
      // skipped for that flush rather than piling more data into an
      // already-unconsumed buffer — bounds per-connection memory growth.
      this.MAX_CLIENT_BUFFERED_BYTES = 2 * 1024 * 1024; // 2MB
      this.reconnectTimer = null;
      this.isKiteConnected = false;
      this.autoLoginAttempted = false;
      this._consecutiveFails = 0;
      this._lastErrorWas403 = false;
      this.pendingTokensCache = new Set();

      // ── Tick watchdog ──────────────────────────────────────────────
      // Detects a "zombie" Kite connection: the socket is still OPEN (so the
      // 'close'/'error' handlers never fire and the normal reconnect never
      // triggers) but no ticks are arriving. Kite streams a heartbeat roughly
      // every second while connected, so a multi-second silence during a
      // trading session reliably means the feed is dead even though TCP is up.
      this._lastTickAt = 0;                  // epoch ms of last tick received
      this._watchdogTimer = null;            // setInterval handle
      this._watchdogRecovering = false;      // guard against overlapping forced reconnects
      this.TICK_STALE_MS = 15000;            // no tick for 15s → treat as dead
      this.WATCHDOG_INTERVAL_MS = 5000;      // check every 5s
    }

  /**
   * Initialize WebSocket server on the HTTP server
   */
  init(server, options = {}) {
    this.wss = new WebSocket.Server({ noServer: true });
    console.log('📡 WebSocket server initialized (noServer mode)');

    this.wss.on('connection', (ws) => {
      console.log('🔌 New Flutter client connected');
      console.log(`   Total clients: ${this.wss.clients.size}`);
      this.clients.add(ws);

      ws.on('message', (message) => {
        try {
          const data = JSON.parse(message);
          // Never log the auth token itself (a client's login would be readable from the log).
          console.log('📩 Received from client:', JSON.stringify(data && data.token ? { ...data, token: '<redacted>' } : data));
          this._handleClientMessage(ws, data);
        } catch (e) {
          console.log('❌ Invalid message from client:', e.message);
        }
      });

      ws.on('close', () => {
        console.log('🔌 Flutter client disconnected');
        this.clients.delete(ws);
        this._unregisterClientUserId(ws);
        console.log(`   Remaining clients: ${this.wss.clients.size}`);
        this._cleanupUnusedTokens();
      });

      ws.on('error', (err) => {
        console.log('❌ Client WebSocket error:', err.message);
      });

      // Send connection confirmation
      ws.send(JSON.stringify({
        type: 'connected',
        message: 'Connected to live price server',
        kiteConnected: this.isKiteConnected,
      }));
    });

    // DB-backed prices are loaded explicitly after connectDatabase/index sync in
    // the startup sequence, before metricsEngine becomes ready.

    // The startup barrier can register WebSocket handlers before listening while
    // deferring outbound Kite connectivity until DB, recovery, and metrics are ready.
    if (options.connectKite !== false) this._connectToKite();
  }

  /**
   * Pre-load the durable official settlement price during the weekend. The
   * daily Kite instrument CSV can carry last_price=0, so settlement_price (or
   * legacy ohlc_close) is authoritative until the next market session.
   */
  async _preloadSettlementPrices(options = {}) {
    try {
      if (!this._settlementPrices) this._settlementPrices = new Map();
      const weekend = isWeekendInIndia(options.now || new Date());
      if (!weekend) this._settlementPrices.clear();
      const latestRun = weekend
        ? await SettlementRun.findOne({ status: { $in: ['committed', 'finalizing', 'completed'] } }).sort({ trading_date: -1 }).select('trading_date').lean()
        : null;
      const activeRange = latestRun ? dateRange(latestRun.trading_date) : null;

      const instruments = await KiteInstrument.find({
        is_active: true,
        deleted_at: null,
        $or: [
          { settlement_price: { $gt: 0 } },
          { last_price: { $gt: 0 } },
          { ohlc_close: { $gt: 0 } },
        ],
      }).select('instrument_token settlement_price settlement_price_date last_price ohlc_close').lean();

      let loaded = 0;
      for (const inst of instruments) {
        const tokenStr = inst.instrument_token.toString();
        const settlementDate = inst.settlement_price_date ? new Date(inst.settlement_price_date) : null;
        const settlementIsCurrent = !activeRange || (settlementDate && settlementDate >= activeRange.start && settlementDate < activeRange.end);
        const price = weekend
          ? ((settlementIsCurrent ? inst.settlement_price : 0) || inst.ohlc_close || inst.last_price)
          : inst.last_price;
        if (!price || price <= 0) continue;

        if (weekend) this._settlementPrices.set(tokenStr, price);
        this.latestPrices.set(tokenStr, price);
        this.latestPrices.set(Number(tokenStr), price);
        loaded++;
      }

      console.log(`📊 [Settlement] Pre-loaded ${loaded} ${weekend ? 'weekend settlement' : 'latest'} prices from DB.`);
    } catch (e) {
      console.error(`❌ [Settlement] Error pre-loading prices from DB: ${e.message}`);
    }
  }

  /**
   * Authenticate a WS client from its signed JWT.
   *
   * Security model (fixes the auth-bypass where the client could claim any
   * userId/role):
   *   • Identity (id + role) ALWAYS comes from a verified JWT, never from the
   *     client's message body.
   *   • A plain user's stream is always their own id.
   *   • A master/admin may request to VIEW a specific downstream account's
   *     stream via `viewAsUserId` — but only if that target is within their
   *     own hierarchy. Otherwise the request is refused and they stay on their
   *     own id.
   */
  async _authenticateClient(ws, data) {
    const token = data.token;
    if (!token) {
      console.log('⚠️  [WS] auth rejected — no token provided');
      try { ws.send(JSON.stringify({ type: 'auth_error', message: 'Authentication token required' })); } catch (_) {}
      return;
    }

    let decoded;
    try {
      decoded = jwt.verify(token, process.env.JWT_SECRET);
    } catch (err) {
      console.log(`⚠️  [WS] auth rejected — invalid token: ${err.message}`);
      try { ws.send(JSON.stringify({ type: 'auth_error', message: 'Invalid or expired token' })); } catch (_) {}
      return;
    }

    const callerId = decoded.id?.toString();
    const callerRole = decoded.role; // 'user' | 'master' | 'admin'
    if (!callerId) {
      try { ws.send(JSON.stringify({ type: 'auth_error', message: 'Malformed token' })); } catch (_) {}
      return;
    }

    // Default: the connection represents the caller themselves.
    ws.authUserId = callerId;
    ws.role = callerRole;
    ws.isAdmin = callerRole === 'admin';
    // Masters hidden from this admin (whole subtrees) — live trade alerts for
    // their clients are not sent to this connection (metricsEngine
    // .broadcastTradeAlert). Super admin / nothing hidden: null.
    ws.hiddenMasterIds = null;
    if (ws.isAdmin) {
      try {
        const Admin = require('../models/Admin');
        const adminDoc = await Admin.findById(callerId).select('is_super_admin hidden_master_ids').lean();
        const { getAdminHiddenMasterIds } = require('./masterHierarchyService');
        const hidden = await getAdminHiddenMasterIds({
          isSuperAdmin: !!adminDoc?.is_super_admin,
          hiddenMasterIds: (adminDoc?.hidden_master_ids || []).map(String),
        });
        ws.hiddenMasterIds = hidden.size > 0 ? hidden : null;
      } catch (_) {
        ws.hiddenMasterIds = null;
      }
    }

    // Optional impersonation for the master/admin dashboards: view a specific
    // downstream account's live stream. Must be authorized against the caller's
    // own hierarchy — a user can never view anyone else.
    const target = data.viewAsUserId?.toString();
    if (target && target !== callerId) {
      const allowed = await this._canView(callerId, callerRole, target);
      if (allowed) {
        this._setClientUserId(ws, target);
        console.log(`✅ [WS] ${callerRole} ${callerId} authenticated, viewing downstream account ${target}`);
      } else {
        // Refuse the impersonation but keep them authenticated as themselves.
        this._setClientUserId(ws, callerId);
        console.log(`🚫 [WS] ${callerRole} ${callerId} DENIED view of ${target} (outside hierarchy) — defaulting to self`);
        try { ws.send(JSON.stringify({ type: 'auth_error', message: 'Not authorized to view that account' })); } catch (_) {}
      }
    } else {
      this._setClientUserId(ws, callerId);
    }

    console.log(`✅ [WS] Authenticated: ${callerId} (${callerRole})${ws.isAdmin ? ' [admin]' : ''} → stream userId=${ws.userId}`);
    try { ws.send(JSON.stringify({ type: 'auth_ok', userId: ws.userId })); } catch (_) {}
  }

  /**
   * Keep this.userClients (userId -> Set<ws>) in sync with a client's
   * current stream identity — a client can re-authenticate or switch
   * `viewAsUserId` mid-connection, so the old mapping must be removed
   * before the new one is added, not just overwritten on the ws object.
   */
  _setClientUserId(ws, userId) {
    this._unregisterClientUserId(ws);
    ws.userId = userId;
    if (!this.userClients.has(userId)) this.userClients.set(userId, new Set());
    this.userClients.get(userId).add(ws);
  }

  _unregisterClientUserId(ws) {
    if (!ws.userId || !this.userClients.has(ws.userId)) return;
    const set = this.userClients.get(ws.userId);
    set.delete(ws);
    if (set.size === 0) this.userClients.delete(ws.userId);
  }

  /**
   * Can `callerId` (role) receive the live stream of `targetUserId`?
   *   • admin  → anyone
   *   • master → any User or Master within their own sub-tree
   *   • user   → only themselves (handled by caller; returns false here)
   */
  async _canView(callerId, callerRole, targetUserId) {
    try {
      if (callerRole === 'admin') return true;
      if (callerRole !== 'master') return false; // users cannot view others

      const { getAllSubMasterIds } = require('./masterHierarchyService');
      const subtreeMasterIds = await getAllSubMasterIds(callerId); // includes callerId

      // Target is a master within the sub-tree?
      if (subtreeMasterIds.includes(targetUserId)) return true;

      // Target is a user whose master is within the sub-tree?
      const User = require('../models/User');
      const target = await User.findById(targetUserId).select('master_id deleted_at').lean();
      if (!target || target.deleted_at) return false;
      return !!target.master_id && subtreeMasterIds.includes(target.master_id.toString());
    } catch (err) {
      console.log(`⚠️  [WS] _canView error: ${err.message}`);
      return false; // fail closed
    }
  }

  /**
   * Handle messages from Flutter clients
   */
  _handleClientMessage(ws, data) {
    switch (data.type) {
      case 'auth':
        // Auth is verified against the signed JWT — never the client's claim.
        // Runs async; errors are swallowed inside _authenticateClient.
        this._authenticateClient(ws, data);
        break;

      case 'subscribe':
        if (data.tokens && Array.isArray(data.tokens)) {
          console.log(`📊 Subscribe request for tokens: ${data.tokens.join(', ')}`);
          data.tokens.forEach(token => {
            const numToken = parseInt(token);
            if (!isNaN(numToken)) {
              this.subscribedTokens.add(numToken);
            }
          });
          this._updateKiteSubscription();

          // Send cached prices immediately for newly subscribed tokens
          // Uses settlement prices (from bhavcopy) when available — these show during closed market hours
          // Live ticks from Kite will override these when market opens
          const cachedTicks = [];
          for (const token of data.tokens) {
            const tokenStr = token.toString();
            // Prefer settlement price (from bhavcopy), fall back to latest live price
            const settlementPrice = this._settlementPrices?.get(tokenStr);
            const livePrice = this.latestPrices.get(tokenStr) || this.latestPrices.get(parseInt(tokenStr));
            const price = settlementPrice || livePrice;
            if (price && price > 0) {
              cachedTicks.push({
                instrument_token: tokenStr,
                last_price: price,
                bid_price: price,
                ask_price: price,
                close: settlementPrice || price,
                is_settlement: !!settlementPrice,
              });
            }
          }
          if (cachedTicks.length > 0 && ws.readyState === 1) {
            ws.send(JSON.stringify({ type: 'ticks', data: cachedTicks }));
          }
        }
        break;

      case 'unsubscribe':
        if (data.tokens && Array.isArray(data.tokens)) {
          console.log(`📊 Unsubscribe request for tokens: ${data.tokens.join(', ')}`);
          data.tokens.forEach(token => {
            this.subscribedTokens.delete(parseInt(token));
          });
          this._updateKiteSubscription();
        }
        break;

      default:
        console.log(`❓ Unknown message type: ${data.type}`);
    }
  }

  /**
   * Connect to Kite WebSocket for live market data
   */
  async _connectToKite() {
      try {
        const accessToken = await kiteService.getStoredAccessToken();
        if (!accessToken) {
          console.log('⚠️  No Kite access token available for WebSocket');

          // Try auto-login once
          if (!this.autoLoginAttempted) {
            this.autoLoginAttempted = true;
            console.log('🤖 Attempting auto-login...');

            const kiteAuthService = require('./kiteAuthService');
            const loginResult = await kiteAuthService.performAutomatedLogin();

            if (loginResult.success) {
              console.log('✅ Auto-login successful, connecting to WebSocket...');
              return this._connectToKite();
            } else {
              console.log('❌ Auto-login failed:', loginResult.error);
            }
          }

          console.log('   Will retry in 30 seconds...');
          this.reconnectTimer = setTimeout(() => this._connectToKite(), 30000);
          return;
        }

        const apiKey = process.env.KITE_API_KEY;
        const wsUrl = `wss://ws.kite.trade?api_key=${apiKey}&access_token=${accessToken}`;

        console.log('🔌 Connecting to Kite WebSocket...');

        this.kiteTicker = new WebSocket(wsUrl);

        this.kiteTicker.on('open', () => {
          console.log('✅ Connected to Kite WebSocket');
          this.isKiteConnected = true;
          this.autoLoginAttempted = false; // Reset for next disconnect
          this._consecutiveFails = 0;
          this._watchdogRecovering = false;
          // Seed last-tick time so the watchdog gives the feed a full stale
          // window to start flowing before considering it dead.
          this._lastTickAt = Date.now();
          this._startTickWatchdog();
          this._broadcastToClients({
            type: 'kite_status',
            connected: true,
          });
          this._updateKiteSubscription();
        });

        this.kiteTicker.on('message', (data) => {
          this._lastTickAt = Date.now();
          this._processKiteTick(data);
        });

        this.kiteTicker.on('close', (code, reason) => {
          console.log(`⚠️  Kite WebSocket closed: ${code} - ${reason}`);
          this.isKiteConnected = false;
          this._broadcastToClients({
            type: 'kite_status',
            connected: false,
          });

          // Track consecutive failures
          this._consecutiveFails = (this._consecutiveFails || 0) + 1;

          // 1006 with a prior 403 error means token is rejected by Kite
          // Try auto-login to get a fresh token before reconnecting
          if (this._lastErrorWas403 && !this.autoLoginAttempted) {
            this._lastErrorWas403 = false;
            this.autoLoginAttempted = true;
            console.log('🔑 403 detected — attempting auto-login for fresh token...');
            const kiteAuthService = require('./kiteAuthService');
            kiteAuthService.performAutomatedLogin().then(result => {
              if (result.success) {
                console.log('✅ Auto-login successful, reconnecting WebSocket...');
                this.autoLoginAttempted = false;
                this._consecutiveFails = 0;
                this._connectToKite();
              } else {
                console.log('❌ Auto-login failed:', result.error);
                console.log('   Will retry in 60 seconds...');
                this.reconnectTimer = setTimeout(() => {
                  this.autoLoginAttempted = false;
                  this._connectToKite();
                }, 60000);
              }
            });
            return;
          }

          // Back off on repeated failures: 5s, 10s, 20s, 30s max
          const delay = Math.min(5000 * Math.pow(2, this._consecutiveFails - 1), 30000);
          console.log(`   Reconnecting in ${delay / 1000}s... (attempt ${this._consecutiveFails})`);
          this.reconnectTimer = setTimeout(() => this._connectToKite(), delay);
        });

        this.kiteTicker.on('error', (err) => {
          console.log('❌ Kite WebSocket error:', err.message);
          this.isKiteConnected = false;
          // Flag if this was a 403 so the close handler can act on it
          if (err.message && err.message.includes('403')) {
            this._lastErrorWas403 = true;
          }
        });

      } catch (error) {
        console.error('❌ Error connecting to Kite WebSocket:', error.message);
        this.reconnectTimer = setTimeout(() => this._connectToKite(), 10000);
      }
    }

  /**
   * Start (or restart) the tick watchdog. Periodically checks whether ticks
   * are still flowing on a socket that reports OPEN. If the feed has gone
   * silent past TICK_STALE_MS during a trading session, the connection is a
   * zombie — force a clean reconnect that the normal close/error path missed.
   */
  _startTickWatchdog() {
    if (this._watchdogTimer) clearInterval(this._watchdogTimer);
    this._watchdogTimer = setInterval(() => this._checkTickFreshness(), this.WATCHDOG_INTERVAL_MS);
  }

  _stopTickWatchdog() {
    if (this._watchdogTimer) {
      clearInterval(this._watchdogTimer);
      this._watchdogTimer = null;
    }
  }

  _checkTickFreshness() {
    // Only meaningful when the socket claims to be open.
    if (!this.kiteTicker || this.kiteTicker.readyState !== WebSocket.OPEN) return;
    // Nothing subscribed → no ticks expected, silence is normal.
    if (this.subscribedTokens.size === 0 && this.pendingTokensCache.size === 0) return;
    // No market on weekends → don't churn the connection pointlessly.
    // (Weekday holidays still fall through, but a reconnect then is harmless.)
    if (isWeekendInIndia()) return;
    // Avoid stacking forced reconnects while one is already in flight.
    if (this._watchdogRecovering) return;

    const age = Date.now() - this._lastTickAt;
    if (age <= this.TICK_STALE_MS) return;

    console.log(`🚨 [TickWatchdog] No Kite ticks for ${(age / 1000).toFixed(1)}s while socket reports OPEN — forcing reconnect (zombie connection).`);
    this._watchdogRecovering = true;
    this._stopTickWatchdog();
    this.isKiteConnected = false;
    this._broadcastToClients({ type: 'kite_status', connected: false });

    try {
      // Terminate the dead socket. If 'close' fires it will schedule its own
      // reconnect; the explicit reconnect below covers the case where the
      // zombie socket never emits 'close' at all.
      this.kiteTicker.terminate();
    } catch (err) {
      console.log(`   ⚠️  [TickWatchdog] terminate() error: ${err.message}`);
    }

    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = setTimeout(() => this._connectToKite(), 1000);
  }

  /**
   * Add a pending limit order token to the cache so it receives price updates
   * @param {string|number} token
   */
  addPendingToken(token) {
    if (!token) return;
    const numToken = Number(token);
    if (!this.pendingTokensCache.has(numToken)) {
      this.pendingTokensCache.add(numToken);
      this._updateKiteSubscription(); // Refresh subscription immediately
    }
  }

  /**
   * Remove a pending limit order token when it's executed or cancelled
   * @param {string|number} token 
   */
  removePendingToken(token) {
    if (!token) return;
    const numToken = Number(token);
    if (this.pendingTokensCache.has(numToken)) {
      this.pendingTokensCache.delete(numToken);
      // We don't strictly need to force an immediate unsubscribe, 
      // it will be cleaned up on the next natural _updateKiteSubscription cycle if no longer needed.
    }
  }

  /** Make sure these tokens are on the Kite feed (e.g. a just-opened next contract). */
  ensureSubscribed(tokens) {
    let added = 0;
    for (const t of tokens || []) {
      const numToken = parseInt(t);
      if (!isNaN(numToken) && !this.subscribedTokens.has(numToken)) {
        this.subscribedTokens.add(numToken);
        added++;
      }
    }
    if (added) this._updateKiteSubscription();
    return added;
  }

  /**
   * Update Kite subscription with current tokens
   */
  _updateKiteSubscription() {
    if (!this.kiteTicker || this.kiteTicker.readyState !== WebSocket.OPEN) {
      console.log('⚠️  Kite WebSocket not ready, skipping subscription update');
      return;
    }

    // Include synthetic instrument source tokens so they always get ticks
    const syntheticSourceTokens = syntheticInstrumentService.getSourceTokens();
    syntheticSourceTokens.forEach(t => this.subscribedTokens.add(t));

    // Include all tokens with open positions so metricsEngine can check margin square-off
    try {
      const metricsEngine = require('./metricsEngine');
      const positionTokens = metricsEngine.getPositionTokens();
      positionTokens.forEach(t => this.subscribedTokens.add(t));
    } catch (_) {}

    // Include all pending limit order tokens so they trigger when price reaches limit
    if (this.pendingTokensCache) {
      this.pendingTokensCache.forEach(t => this.subscribedTokens.add(t));
    }

    // Next contracts in their rollover window (opened, old contract not cut
    // yet) — rollover reopens at their live price even if nobody watches them.
    try {
      const expiryActionService = require('./expiryActionService');
      expiryActionService.getRolloverTokens().forEach(t => {
        const numToken = parseInt(t);
        if (!isNaN(numToken)) this.subscribedTokens.add(numToken);
      });
    } catch (_) {}

    // GIFT NIFTY monthly contracts are priced from NSE IX (giftNiftyFeedService),
    // not Kite — their tokens (>= 9,900,000,000) never go to Kite.
    const tokens = Array.from(this.subscribedTokens).filter(t => Number(t) < 9_900_000_000);
    if (tokens.length === 0) {
      console.log('📊 No tokens to subscribe');
      return;
    }

    console.log(`📊 Subscribing to ${tokens.length} tokens on Kite: ${tokens.join(', ')}`);

    // Subscribe message for Kite WebSocket
    const subscribeMsg = JSON.stringify({
      a: 'subscribe',
      v: tokens,
    });
    this.kiteTicker.send(subscribeMsg);

    // Set mode to full for all tokens (full tick data)
    const modeMsg = JSON.stringify({
      a: 'mode',
      v: ['full', tokens],
    });
    this.kiteTicker.send(modeMsg);

    console.log('   ✅ Subscription sent to Kite');
  }

  /**
   * Process binary tick data from Kite WebSocket
   */
  _processKiteTick(rawData) {
    try {
      // Kite sends binary data
      const buffer = Buffer.isBuffer(rawData) ? rawData : Buffer.from(rawData);

      // First 2 bytes = number of packets
      if (buffer.length < 2) return;

      const numPackets = buffer.readInt16BE(0);
      let offset = 2;

      const ticks = [];

      for (let i = 0; i < numPackets; i++) {
        if (offset + 2 > buffer.length) break;

        const packetLength = buffer.readInt16BE(offset);
        offset += 2;

        if (offset + packetLength > buffer.length) break;

        const packet = buffer.slice(offset, offset + packetLength);
        offset += packetLength;

        const tick = this._parseTick(packet);
        if (tick) {
          ticks.push(tick);
        }
      }

      if (ticks.length > 0) {
        this._lastRealTickAt = Date.now(); // real prices, not heartbeats (watchdog feed check)
        // Update latest prices map
        const liveTicks = [];
        ticks.forEach(t => {
          if (t && t.instrument_token && t.last_price) {
            const tokenStr = t.instrument_token.toString();

            // Weekend subscription snapshots must not overwrite official prices.
            // On the first weekday tick, release every lock unconditionally — a
            // real session can open at the exact same price as settlement.
            if (this._settlementPrices && this._settlementPrices.size > 0 && !isWeekendInIndia()) {
              console.log('📊 Weekday market tick detected. Clearing weekend settlement-price locks.');
              this._settlementPrices.clear();
              metricsEngine.clearSettledTokens();
            }

            // If settlement price still exists for this specific token, skip watchlist update
            // (but still feed metricsEngine below)
            const stillHasSettlement = this._settlementPrices && this._settlementPrices.has(tokenStr);
            if (!stillHasSettlement) {
              this.latestPrices.set(tokenStr, t.last_price);
              this.latestPrices.set(parseInt(t.instrument_token), t.last_price);
              liveTicks.push(t);
            }

            // ALWAYS update metricsEngine (positions need live data, independent of watchlist)
            metricsEngine.onTick(t.instrument_token, t.last_price, t.bid_price, t.ask_price);

            // Publish price update to BullMQ for order matching
            priceQueueService.publishPriceUpdate(t.instrument_token.toString(), t.last_price);

            // Update synthetic instruments that depend on this source
            syntheticInstrumentService.onTick(t.instrument_token, t.last_price);
          }
        });

        if (LOG_LIVE_TICKS) {
          console.log(`📈 Received ${ticks.length} tick(s):`);
          liveTicks.forEach(t => {
            console.log(`   Token: ${t.instrument_token} | LTP: ${t.last_price}`);
          });
        }

        if (liveTicks.length > 0) {
          this._queueTickBroadcast(liveTicks);
        }
      }
    } catch (error) {
      console.log('❌ Error processing Kite tick:', error.message);
    }
  }

  /**
   * Parse a single tick packet from Kite binary data
   * Ref: https://kite.trade/docs/connect/v3/websocket/
   *
   * Quote packet (44 bytes):
   *   0-3   instrument_token
   *   4-7   last_price (/100)
   *   8-11  last_traded_quantity
   *  12-15  average_traded_price (/100)
   *  16-19  volume
   *  20-23  total_buy_quantity
   *  24-27  total_sell_quantity
   *  28-31  open (/100)
   *  32-35  high (/100)
   *  36-39  low (/100)
   *  40-43  close (/100)
   *
   * Full packet (184 bytes) adds:
   *  44-47  last_traded_timestamp
   *  48-51  oi
   *  52-55  oi_day_high
   *  56-59  oi_day_low
   *  60-63  exchange_timestamp
   *  64-183 market depth (10 entries × 12 bytes: qty(4) + price(4) + orders(2) + pad(2))
   *         entries 0-4 = bids, entries 5-9 = asks
   */
  _parseTick(packet) {
    try {
      if (packet.length < 4) return null;

      const instrumentToken = packet.readInt32BE(0);

      // Determine divisor: currencies use 10000000, everything else 100
      // Segment = token & 0xFF (last byte). CDS segment = 3
      const segment = instrumentToken & 0xFF;
      const divisor = (segment === 3) ? 10000000 : 100;

      // LTP mode (8 bytes) — all instruments
      if (packet.length === 8) {
        const lastPrice = packet.readInt32BE(4) / divisor;
        return {
          instrument_token: instrumentToken.toString(),
          last_price: lastPrice,
        };
      }

      // Index packets: quote=28 bytes, full=32 bytes
      // Structure: token(4), ltp(4), high(4), low(4), open(4), close(4), change(4), [exchange_ts(4)]
      if (packet.length === 28 || packet.length === 32) {
        const lastPrice = packet.readInt32BE(4) / divisor;
        const highPrice = packet.readInt32BE(8) / divisor;
        const lowPrice = packet.readInt32BE(12) / divisor;
        const openPrice = packet.readInt32BE(16) / divisor;
        const closePrice = packet.readInt32BE(20) / divisor;

        const change = lastPrice - closePrice;
        let changePercent = 0;
        if (closePrice > 0.01) {
          changePercent = (change / closePrice) * 100;
          changePercent = Math.max(-100, Math.min(1000, changePercent));
        }

        return {
          instrument_token: instrumentToken.toString(),
          last_price: lastPrice,
          high: highPrice,
          low: lowPrice,
          open: openPrice,
          close: closePrice,
          change,
          change_percent: changePercent,
        };
      }

      // Quote mode (44 bytes) or Full mode (184 bytes)
      if (packet.length >= 44) {
        const lastPrice = packet.readInt32BE(4) / divisor;
        const openPrice = packet.readInt32BE(28) / divisor;
        const highPrice = packet.readInt32BE(32) / divisor;
        const lowPrice = packet.readInt32BE(36) / divisor;
        const closePrice = packet.readInt32BE(40) / divisor;

        const change = lastPrice - closePrice;
        let changePercent = 0;

        if (closePrice > 0.01) {
          changePercent = (change / closePrice) * 100;
          changePercent = Math.max(-100, Math.min(1000, changePercent));
        }

        const tick = {
          instrument_token: instrumentToken.toString(),
          last_price: lastPrice,
          high: highPrice,
          low: lowPrice,
          open: openPrice,
          close: closePrice,
          change: change,
          change_percent: changePercent,
        };

        // Full mode (184 bytes) includes market depth starting at byte 64
        if (packet.length >= 184) {
          try {
            // Market depth: each entry = qty(4) + price(4) + orders(2) + pad(2) = 12 bytes
            // Best bid (first buy entry): price at offset 64 + 4 = 68
            // Best ask (first sell entry, after 5 buy entries): price at offset 64 + (5*12) + 4 = 128
            const bestBidPrice = packet.readInt32BE(68) / divisor;
            const bestAskPrice = packet.readInt32BE(128) / divisor;

            if (bestBidPrice > 0) {
              tick.bid_price = bestBidPrice;
            }
            if (bestAskPrice > 0) {
              tick.ask_price = bestAskPrice;
            }
          } catch (err) {
            console.log(`   ⚠️  Error parsing market depth: ${err.message}`);
          }
        }

        return tick;
      }

      // Minimal parse
      if (packet.length >= 8) {
        const lastPrice = packet.readInt32BE(4) / 100;
        return {
          instrument_token: instrumentToken.toString(),
          last_price: lastPrice,
        };
      }

      return null;
    } catch (error) {
      console.log('❌ Error parsing tick packet:', error.message);
      return null;
    }
  }

  /**
   * Broadcast data to all connected Flutter clients.
   * Callers wanting throttled tick broadcast should use _queueTickBroadcast
   * instead — this still sends immediately (used for non-tick events like
   * connection status, where coalescing wouldn't make sense).
   */
  _broadcastToClients(data) {
    const message = JSON.stringify(data);
    let sentCount = 0;

    if (this.wss) {
      this.wss.clients.forEach((client) => {
        if (client.readyState !== WebSocket.OPEN) return;
        // Backpressure: skip a client whose outgoing buffer is already
        // backed up rather than piling more unconsumed data onto it —
        // unbounded here meant one slow/stalled connection's memory could
        // grow forever under sustained tick volume.
        if (client.bufferedAmount > this.MAX_CLIENT_BUFFERED_BYTES) return;
        client.send(message);
        sentCount++;
      });
    }

    if (data.type === 'ticks' && LOG_LIVE_TICKS) {
      console.log(`   📤 Broadcasted to ${sentCount} client(s)`);
    }
  }

  /**
   * Merge incoming ticks into the pending batch (last tick per instrument
   * wins) and schedule a single coalesced flush at most every
   * BROADCAST_THROTTLE_MS — caps client-facing broadcast frequency without
   * delaying metricsEngine/priceQueueService, which read each tick directly
   * in _processKiteTick before this is ever called.
   */
  _queueTickBroadcast(ticks) {
    for (const t of ticks) {
      this._pendingBroadcastTicks.set(t.instrument_token, t);
    }
    if (this._broadcastFlushTimer) return;
    this._broadcastFlushTimer = setTimeout(() => {
      this._broadcastFlushTimer = null;
      if (this._pendingBroadcastTicks.size === 0) return;
      const data = Array.from(this._pendingBroadcastTicks.values());
      this._pendingBroadcastTicks.clear();
      this._broadcastToClients({ type: 'ticks', data });
    }, this.BROADCAST_THROTTLE_MS);
  }

  /**
   * Send data to a specific user's WebSocket connection(s).
   * Requires the client to have sent an 'auth' message with userId.
   *
   * @param {string} userId - The user's MongoDB _id
   * @param {object} data   - The payload to send
   */
  broadcastToUser(userId, data) {
    if (!this.wss) return;

    const clients = this.userClients.get(userId);
    if (!clients || clients.size === 0) return;

    const message = JSON.stringify(data);
    let sentCount = 0;

    for (const client of clients) {
      if (client.readyState !== WebSocket.OPEN) continue;
      if (client.bufferedAmount > this.MAX_CLIENT_BUFFERED_BYTES) continue;
      client.send(message);
      sentCount++;
    }

    if (sentCount > 0 && LOG_WS_BROADCAST) {
      console.log(`📤 [WS] Sent '${data.type}' to user ${userId} (${sentCount} connection(s))`);
    }
  }

  /**
   * Remove tokens that no clients need anymore.
   * Always keeps position tokens subscribed for margin square-off monitoring.
   */
  _cleanupUnusedTokens() {
    if (this.wss && this.wss.clients.size === 0) {
      console.log('🧹 No clients connected, clearing client subscriptions and latest prices');
      this.subscribedTokens.clear();
      this.latestPrices.clear();
      // Re-add position tokens so margin square-off still works
      try {
        const metricsEngine = require('./metricsEngine');
        const positionTokens = metricsEngine.getPositionTokens();
        positionTokens.forEach(t => this.subscribedTokens.add(t));
        if (positionTokens.length > 0) {
          this._updateKiteSubscription();
        }
      } catch (_) {}
    }
  }

  /**
   * Shutdown gracefully
   */
  shutdown() {
    console.log('🛑 Shutting down LivePriceService...');
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this._stopTickWatchdog();
    if (this.kiteTicker) this.kiteTicker.close();
    if (this.wss) this.wss.close();
  }

  /**
   * Fetch official settlement/close prices from Kite Historical API
   * and broadcast them to all connected Flutter clients.
   * Called via cron after market close.
   *
   * Uses Kite Historical daily candle API — the daily candle `close` field
   * is the official settlement price (not the last traded price).
   * Runs with concurrency control to avoid rate limits.
   */
  async refreshClosePrices() {
      try {
        // Gather tokens from: 1) currently subscribed clients, 2) all watchlists in DB
        const Watchlist = require('../models/Watchlist');
        const watchlistTokens = await Watchlist.distinct('instrument_token', { deleted_at: null });

        const allTokens = new Set([
          ...Array.from(this.subscribedTokens).map(t => t.toString()),
          ...watchlistTokens.map(t => t.toString()),
        ].filter(t => Number(t) < 9_900_000_000)); // NSE IX GIFT contracts: not Kite

        if (allTokens.size === 0) {
          console.log('📊 [refreshClosePrices] No tokens found, skipping.');
          return;
        }

        console.log(`📊 [refreshClosePrices] Refreshing close prices for ${allTokens.size} tokens...`);

        // Date range: today and 5 days back (covers weekends + holidays)
        const today = new Date();
        const daysBack = new Date(today);
        daysBack.setDate(today.getDate() - 5);
        const fmt = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
        const fromDate = fmt(daysBack);
        const toDate = fmt(today);

        const ticks = [];
        const dbBulkOps = [];
        const instrumentOps = [];
        let failed = 0;

        // Process tokens with concurrency limit to avoid Kite rate limits
        const tokenArray = [...allTokens];
        const CONCURRENCY = 5;

        for (let i = 0; i < tokenArray.length; i += CONCURRENCY) {
          const batch = tokenArray.slice(i, i + CONCURRENCY);
          const results = await Promise.allSettled(
            batch.map(async (tokenStr) => {
              const candles = await kiteService.getHistoricalData(tokenStr, 'day', fromDate, toDate);
              if (!candles || candles.length === 0) return null;

              const lastCandle = candles[candles.length - 1];
              const closePrice = lastCandle.close;
              if (!closePrice || closePrice <= 0) return null;

              return { tokenStr, closePrice, open: lastCandle.open, high: lastCandle.high, low: lastCandle.low };
            })
          );
          for (const result of results) {
            if (result.status !== 'fulfilled' || !result.value) {
              if (result.status === 'rejected') failed++;
              continue;
            }
            const { tokenStr, closePrice, open, high, low } = result.value;

            // Update in-memory latest prices
            this.latestPrices.set(tokenStr, closePrice);
            this.latestPrices.set(parseInt(tokenStr), closePrice);

            ticks.push({
              instrument_token: tokenStr,
              last_price: closePrice,
              open: open || 0,
              high: high || 0,
              low: low || 0,
            });

            dbBulkOps.push({
              updateOne: {
                filter: { instrument_token: tokenStr },
                update: { $set: { instrument_token: tokenStr, last_price: closePrice, timestamp: new Date() } },
                upsert: true
              }
            });

            instrumentOps.push({
              updateOne: {
                filter: { instrument_token: tokenStr },
                update: { $set: {
                  last_price: closePrice,
                  ohlc_open: open || 0,
                  ohlc_high: high || 0,
                  ohlc_low: low || 0,
                  ohlc_close: closePrice,
                } }
              }
            });
          }

          // Small delay between batches to respect rate limits
          if (i + CONCURRENCY < tokenArray.length) {
            await new Promise(r => setTimeout(r, 500));
          }
        }

        // Broadcast corrected prices to Flutter clients
        if (ticks.length > 0) {
          console.log(`📊 [refreshClosePrices] Broadcasting ${ticks.length} corrected close prices (${failed} failed)`);
          this._broadcastToClients({ type: 'ticks', data: ticks });
        }

        // Update KiteMarketQuote DB
        if (dbBulkOps.length > 0) {
          await KiteMarketQuote.bulkWrite(dbBulkOps, { ordered: false });
          console.log(`📊 [refreshClosePrices] Updated ${dbBulkOps.length} quotes in KiteMarketQuote`);
        }

        // Update KiteInstrument.last_price so app reload shows correct price
        if (instrumentOps.length > 0) {
          await KiteInstrument.bulkWrite(instrumentOps, { ordered: false });
          console.log(`📊 [refreshClosePrices] Updated ${instrumentOps.length} KiteInstrument last_price values`);
        }

        console.log('✅ [refreshClosePrices] Done.');
        return { tokensFound: allTokens.size, ticksBroadcast: ticks.length, dbUpdated: dbBulkOps.length, failed, clientsConnected: this.wss ? this.wss.clients.size : 0 };
      } catch (error) {
        console.error('❌ [refreshClosePrices] Error:', error.message);
        return { error: error.message };
      }
    }

  /**
   * Fetch official settlement prices using Kite OHLC Quote API (batch).
   * ohlc.close = previous day's official settlement price.
   *
   * For NSE: available by ~6 PM same day.
   * For MCX: available by ~8-9 AM next morning.
   *
   * KEY: Only queries active, non-expired instruments to avoid silent drops.
   */
  async refreshSettlementPrices() {
    try {
      // Only refresh prices for tokens that matter:
      // 1. Currently subscribed (WebSocket clients watching)
      // 2. In watchlists
      // 3. With open positions (from metricsEngine)
      const Watchlist = require('../models/Watchlist');
      const watchlistTokens = await Watchlist.distinct('instrument_token', { deleted_at: null });

      let positionTokens = [];
      try {
        const metricsEngine = require('./metricsEngine');
        for (const [token] of metricsEngine._tokenToUsers || new Map()) {
          positionTokens.push(token);
        }
      } catch (_) {}

      const allTokens = new Set([
        ...Array.from(this.subscribedTokens).map(t => t.toString()),
        ...watchlistTokens.map(t => t.toString()),
        ...positionTokens,
      ].filter(t => Number(t) < 9_900_000_000)); // NSE IX GIFT contracts: not Kite

      if (allTokens.size === 0) {
        console.log('📊 [refreshSettlement] No relevant tokens, skipping.');
        return { total: 0, updated: 0, missing: 0 };
      }

      // Look up exchange:tradingsymbol for these tokens only
      const tokenArray = [...allTokens];
      const instruments = await KiteInstrument.find({
        instrument_token: { $in: tokenArray },
        is_active: true,
      }).select('instrument_token tradingsymbol exchange').lean();

      console.log(`📊 [refreshSettlement] Refreshing ${instruments.length} instruments (from ${allTokens.size} tokens)`);

      // Build EXCHANGE:TRADINGSYMBOL keys
      const keyToToken = new Map();
      const keys = [];
      for (const inst of instruments) {
        const key = `${inst.exchange}:${inst.tradingsymbol.trim()}`;
        keyToToken.set(key, inst.instrument_token.toString());
        keys.push(key);
      }

      if (keys.length === 0) {
        console.log('📊 [refreshSettlement] No keys to query, skipping.');
        return { total: 0, updated: 0, missing: 0 };
      }

      // 3. Batch OHLC API in chunks of 200
      const BATCH_SIZE = 200;
      const allOhlcData = {};

      for (let i = 0; i < keys.length; i += BATCH_SIZE) {
        const batch = keys.slice(i, i + BATCH_SIZE);
        try {
          const data = await kiteService.getMarketQuotes(batch, 'ohlc');
          Object.assign(allOhlcData, data);
        } catch (err) {
          console.error(`⚠️  [refreshSettlement] Batch ${Math.floor(i / BATCH_SIZE) + 1} failed: ${err.message}`);
        }
      }

      const returnedCount = Object.keys(allOhlcData).length;
      console.log(`📊 [refreshSettlement] OHLC API returned ${returnedCount}/${keys.length} instruments`);

      // Log missing keys for debugging
      const missingKeys = keys.filter(k => !allOhlcData[k]);
      if (missingKeys.length > 0 && missingKeys.length <= 20) {
        console.warn(`⚠️  [refreshSettlement] Missing from OHLC (${missingKeys.length}):`, missingKeys.join(', '));
      } else if (missingKeys.length > 20) {
        console.warn(`⚠️  [refreshSettlement] ${missingKeys.length} instruments missing from OHLC response`);
      }

      // 4. Build bulk updates
      const ticks = [];
      const bulkOps = [];

      for (const [instKey, quote] of Object.entries(allOhlcData)) {
        const tokenStr = keyToToken.get(instKey);
        if (!tokenStr || !quote) continue;

        const ohlc = quote.ohlc || {};
        const settlementPrice = ohlc.close;
        if (!settlementPrice || settlementPrice <= 0) continue;

        // Update in-memory
        this.latestPrices.set(tokenStr, settlementPrice);
        this.latestPrices.set(parseInt(tokenStr), settlementPrice);

        ticks.push({
          instrument_token: tokenStr,
          last_price: settlementPrice,
          open: ohlc.open || 0,
          high: ohlc.high || 0,
          low: ohlc.low || 0,
          close: settlementPrice,
        });

        bulkOps.push({
          updateOne: {
            filter: { instrument_token: tokenStr },
            update: { $set: {
              last_price: settlementPrice,
              ohlc_open: ohlc.open || 0,
              ohlc_high: ohlc.high || 0,
              ohlc_low: ohlc.low || 0,
              ohlc_close: settlementPrice,
            } },
          }
        });
      }

      // 5. Broadcast to Flutter clients
      if (ticks.length > 0) {
        console.log(`📊 [refreshSettlement] Broadcasting ${ticks.length} settlement prices`);
        this._broadcastToClients({ type: 'ticks', data: ticks });
      }

      // 6. Update DB
      if (bulkOps.length > 0) {
        await KiteInstrument.bulkWrite(bulkOps, { ordered: false });
        console.log(`📊 [refreshSettlement] Updated ${bulkOps.length} KiteInstrument last_price values`);
      }

      console.log('✅ [refreshSettlement] Done.');
      return { total: instruments.length, updated: bulkOps.length, missing: missingKeys.length };
    } catch (error) {
      console.error('❌ [refreshSettlement] Error:', error.message);
      return { error: error.message };
    }
  }

}

module.exports = new LivePriceService();
