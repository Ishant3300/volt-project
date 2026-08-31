/**
 * Redis Service
 * 
 * Manages the Redis connection used by both the Order Book (sorted sets)
 * and BullMQ (queues). Provides a singleton IORedis instance and a
 * health-check helper so callers can gracefully fall back to MongoDB
 * when Redis is unavailable.
 */

const Redis = require('ioredis');
const EventEmitter = require('events');
const { LOG_REDIS_ORDERS } = require('../config/logFlags');

const _ts = () => new Date().toISOString();

class RedisService extends EventEmitter {
  constructor() {
    super();
    this.client = null;
    this.isConnected = false;
    this._lastAvailableState = null; // Track state transitions
    this._lastStateChangeAt = null;
    this._disconnectCount = 0;
  }

  /**
   * Initialise (or return existing) Redis connection.
   * Call once at server startup; every other service imports the singleton.
   */
  init() {
    if (this.client) return this.client;

    const redisUrl = process.env.REDIS_URL || 'redis://127.0.0.1:6379';

    this.client = new Redis(redisUrl, {
      maxRetriesPerRequest: null,   // Required by BullMQ
      enableReadyCheck: true,
      retryStrategy: (times) => {
        // Never give up: keep retrying with capped backoff forever. Previously
        // this returned null after 10 attempts (~30s), which permanently
        // stopped reconnection — if Redis recovered after that window the
        // client never came back to 'ready', so the app was stuck in the
        // slower DB-fallback path until a manual restart. Now it retries
        // indefinitely (capped at 5s) like the rest of the codebase.
        const delay = Math.min(times * 500, 5000);
        // Log loudly the first few attempts, then throttle to avoid log spam
        // during a long outage.
        if (times <= 10 || times % 12 === 0) {
          console.log(`🔄 [Redis] [${_ts()}] Reconnecting in ${delay}ms (attempt ${times})`);
        }
        return delay;
      },
    });

    this.client.on('connect', () => {
      console.log(`✅ [Redis] [${_ts()}] Connected`);
      this.isConnected = true;
      this._emitStateChange(true);
    });

    this.client.on('ready', () => {
      console.log(`✅ [Redis] [${_ts()}] Ready`);
      this.isConnected = true;
      this._emitStateChange(true);
    });

    this.client.on('error', (err) => {
      console.error(`❌ [Redis] [${_ts()}] Error: ${err.message}`);
      this.isConnected = false;
      this._emitStateChange(false);
    });

    this.client.on('close', () => {
      console.log(`⚠️  [Redis] [${_ts()}] Connection closed`);
      this.isConnected = false;
      this._disconnectCount++;
      this._emitStateChange(false);
    });

    return this.client;
  }

  /**
   * Emit 'availabilityChange' event when Redis state transitions.
   * Logs prominently so it's visible in server logs for debugging.
   */
  _emitStateChange(nowAvailable) {
    const wasAvailable = this._lastAvailableState;
    if (wasAvailable === nowAvailable) return; // No actual transition

    const previousChangeAt = this._lastStateChangeAt;
    this._lastAvailableState = nowAvailable;
    this._lastStateChangeAt = new Date();

    const downtime = previousChangeAt && nowAvailable
      ? `${((this._lastStateChangeAt - previousChangeAt) / 1000).toFixed(1)}s`
      : null;

    if (nowAvailable) {
      console.log(`🟢 [Redis] [${_ts()}] STATE CHANGE: UNAVAILABLE → AVAILABLE${downtime ? ` (was down for ${downtime})` : ''} | Total disconnects: ${this._disconnectCount}`);
    } else {
      console.log(`🔴 [Redis] [${_ts()}] STATE CHANGE: AVAILABLE → UNAVAILABLE | Total disconnects: ${this._disconnectCount}`);
    }

    this.emit('availabilityChange', {
      available: nowAvailable,
      timestamp: this._lastStateChangeAt,
      downtime,
      disconnectCount: this._disconnectCount,
    });
  }

  /** Quick health check */
  isAvailable() {
    const available = this.isConnected && this.client && this.client.status === 'ready';
    // Log when callers check availability and it's DOWN (helps trace silent failures)
    if (!available && LOG_REDIS_ORDERS) {
      console.log(`⚠️  [Redis] [${_ts()}] isAvailable() → false | isConnected=${this.isConnected}, status=${this.client?.status || 'no-client'}`);
    }
    return available;
  }

  /** Return the raw IORedis instance (for BullMQ, etc.) */
  getClient() {
    return this.client;
  }

  /** Get Redis health diagnostics for logging */
  getDiagnostics() {
    return {
      isConnected: this.isConnected,
      clientStatus: this.client?.status || 'no-client',
      isAvailable: this.isAvailable(),
      lastStateChangeAt: this._lastStateChangeAt,
      disconnectCount: this._disconnectCount,
    };
  }

  /** Graceful shutdown */
  async shutdown() {
    if (this.client) {
      console.log(`🛑 [Redis] [${_ts()}] Shutting down...`);
      await this.client.quit();
      this.isConnected = false;
    }
  }
}

module.exports = new RedisService();
