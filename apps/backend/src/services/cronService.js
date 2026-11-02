const cron = require('node-cron');
const path = require('path');
const { fork } = require('child_process');
const User = require('../models/User');
const Master = require('../models/Master');
const orderExecutionService = require('./orderExecutionService');
const redisService = require('./redisService');
const { snapshotWeeklySummary, snapshotWeeklyLedger } = require('./weeklySummaryService');
const livePriceService = require('./livePriceService');
const { beginTradeWrite } = require('./tradeWriteFenceService');
// Practice mode (docs/practice-trading.md): jobs that reach Kite / NSE / MCX /
// Massive or plan expiries return immediately — practice has no market data.
const { PRACTICE } = require('../config/practice');

/**
 * True when it is `after` minutes past a weekday's MCX close (IST): 11:30 PM
 * in US summer time, 11:55 PM in US winter (utils/mcxHours.js) — today's, or
 * yesterday's when the slot passes midnight (11:55 PM + 15 = 00:10). The MCX
 * close jobs are scheduled at every possible slot and run only at the one
 * matching the day.
 */
function isMcxCloseSlot(after, now = new Date()) {
    const { mcxCloseMinutesOn } = require('../utils/mcxHours');
    const ist = new Date(now.getTime() + 330 * 60 * 1000);
    const minutes = ist.getUTCHours() * 60 + ist.getUTCMinutes();
    for (const back of [0, 1]) {
        const day = new Date(ist.getTime() - back * 86400000);
        const weekday = day.getUTCDay();
        if (weekday === 0 || weekday === 6) continue;
        if (mcxCloseMinutesOn(day.toISOString().slice(0, 10)) + after === minutes + back * 1440) return true;
    }
    return false;
}

/**
 * Automatic closes at the closing bid/ask (intraday square-off, MCX / NSE
 * expiry and corporate-action cuts) run this long after the close — the
 * bid/ask settles after it (owner, 31 Oct 2026).
 */
const CLOSE_SETTLE_MIN = 15;

class CronService {
    constructor() {
        this.jobs = [];
    }

    /**
     * Initializes all scheduled jobs
     */
    init() {
        console.log('🕒 Initializing Cron Scheduler...');

        // Fetch & sync instruments from Kite every day at 8:00 AM
        // Runs fetchInstruments.js in a child process (it calls process.exit internally)
        const fetchInstrumentsJob = cron.schedule('30 7 * * *', () => {
            if (PRACTICE) return;
            console.log('📡 [CRON] Starting daily instrument fetch...');
            const scriptPath = path.join(__dirname, '../../scripts/fetchInstruments.js');
            const child = fork(scriptPath, [], { silent: true });

            child.stdout.on('data', data => process.stdout.write(`[fetchInstruments] ${data}`));
            child.stderr.on('data', data => process.stderr.write(`[fetchInstruments] ${data}`));

            child.on('exit', code => {
                if (code === 0) {
                    console.log('✅ [CRON] Instrument fetch completed successfully.');
                } else {
                    console.error(`❌ [CRON] Instrument fetch exited with code ${code}.`);
                }
            });
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(fetchInstrumentsJob);

        // Official settlement price for CME/CBOT/COMEX instruments (GC/SI/HG,
        // ES/NQ/YM/RTY/NKD/DVE), daily at 6:00 AM IST. Their session closes
        // land in the early-morning IST hours (e.g. COMEX ~2:30 AM IST,
        // CME index futures ~3:30 AM IST) — 6 AM gives comfortable margin
        // for Massive to have published the completed session's
        // settlement_price by the time this runs. Without this, weekly
        // settlement has no official close for these instruments at all and
        // fails the entire run the moment anyone holds an open position on
        // one (settlementService.js's hasOfficialSettlementAuthority gate).
        const massiveSettlementJob = cron.schedule('0 6 * * *', async () => {
            if (PRACTICE) return;
            console.log('📊 [CRON] Fetching CME/CBOT/COMEX official settlement prices (Massive)...');
            try {
                const { fetchAndApplyMassiveSettlement } = require('./massiveSettlementService');
                await fetchAndApplyMassiveSettlement();
                console.log('✅ [CRON] Massive settlement price fetch completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during Massive settlement price fetch:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(massiveSettlementJob);

        // Snapshot weekly P&L every Sunday at 23:55 (before midnight balance reset)
        const weeklySummarySnapshot = cron.schedule('55 23 * * 0', async () => {
            // A special-session day (utils/specialSessions.js) took this week's
            // snapshot before its session — the session belongs to next week.
            if (require('../utils/specialSessions').isSessionDay(new Date())) {
                console.log('📊 [CRON] Weekly Summary Snapshot skipped — taken before today\'s special session.');
                return;
            }
            console.log('📊 [CRON] Starting Weekly Summary Snapshot...');
            try {
                await snapshotWeeklySummary();
                console.log('✅ [CRON] Weekly Summary Snapshot completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during Weekly Summary Snapshot:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(weeklySummarySnapshot);

        // Same slot as the Weekly Summary Snapshot above, but its own cron
        // entry and its own try/catch — a failure here must never affect
        // that existing snapshot, and vice versa.
        const weeklyLedgerSnapshot = cron.schedule('55 23 * * 0', async () => {
            if (require('../utils/specialSessions').isSessionDay(new Date())) {
                console.log('📒 [CRON] Weekly Ledger Snapshot skipped — taken before today\'s special session.');
                return;
            }
            console.log('📒 [CRON] Starting Weekly Ledger Snapshot...');
            try {
                await snapshotWeeklyLedger();
                console.log('✅ [CRON] Weekly Ledger Snapshot completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during Weekly Ledger Snapshot:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(weeklyLedgerSnapshot);

        // Schedule Weekly Balance Reset at Sunday 00:00 AM
        const weeklyBalanceReset = cron.schedule('0 0 * * 0', async () => {
            console.log('🔄 [CRON] Starting Weekly Balance Reset...');
            try {
                await this.resetWeeklyBalances();
                console.log('✅ [CRON] Weekly Balance Reset completed successfully.');
            } catch (error) {
                console.error('❌ [CRON] Error during Weekly Balance Reset:', error);
            }
        }, { timezone: 'Asia/Kolkata' });

        this.jobs.push(weeklyBalanceReset);

        // DB-fallback limit order check every 10 seconds
        // Only actually queries the DB when Redis is unavailable;
        // when Redis is up, the BullMQ price queue handles execution.
        const limitOrderCheck = cron.schedule('*/10 * * * * *', async () => {
            try {
                await orderExecutionService.processPendingOrders();
            } catch (error) {
                console.error('❌ [CRON] Error during Limit Order check:', error);
            }
        });

        this.jobs.push(limitOrderCheck);

        // ── Redis-vs-MongoDB Order Consistency Audit ──────────────────────
        // Every 2 minutes, verify all pending orders in MongoDB are also in
        // the Redis order book. Detects and auto-heals the exact bug where
        // Redis was briefly down when addOrder() was called, leaving the order
        // in Mongo but never registered for live price matching.
        const orderConsistencyAudit = cron.schedule('*/2 * * * *', async () => {
            try {
                const { runAudit } = require('./orderConsistencyAudit');
                await runAudit({ autoHeal: true, silent: false });
            } catch (error) {
                console.error('❌ [CRON] Error during order consistency audit:', error.message);
            }
        });
        this.jobs.push(orderConsistencyAudit);

        // ── Redis-vs-MongoDB Order Consistency Audit (reverse direction) ──
        // Same 2-minute cadence, opposite check: a Redis order-book entry
        // (ob:{token}:buy/sell/stoprise/stopfall) left behind after its
        // trade filled/cancelled/expired/settled, because removeOrder() is
        // deliberately best-effort and can silently no-op on a Redis
        // hiccup. Individually rare, but with thousands of pending orders a
        // day this is the same slow-leak shape as the price-updates queue
        // incident — catch it here instead of letting it regrow unnoticed.
        const orderConsistencyReverseAudit = cron.schedule('*/2 * * * *', async () => {
            try {
                const { runReverseAudit } = require('./orderConsistencyAudit');
                await runReverseAudit({ autoHeal: true, silent: false });
            } catch (error) {
                console.error('❌ [CRON] Error during reverse order consistency audit:', error.message);
            }
        });
        this.jobs.push(orderConsistencyReverseAudit);

        // ── Kite Token Refresh ─────────────────────────────────────────
        // Every 15 minutes: is the Kite access token still valid — saved expiry AND
        // Kite's own answer (kiteAuthService.checkTokenStatus, 1 Nov 2026)?
        // If expired or expiring soon, perform automated login (same as server startup).
        const kiteTokenRefresh = cron.schedule('*/15 * * * *', async () => {
            if (PRACTICE) return;
            try {
                const kiteAuthService = require('./kiteAuthService');
                const status = await kiteAuthService.checkTokenStatus();

                if (status.valid) {
                    if (new Date().getMinutes() < 15) console.log(`🔐 [CRON] Kite token OK (valid for ${status.hoursLeft} hours${status.live === 'unknown' ? ', Kite did not answer' : ''}).`);
                    return;
                }

                console.log(`⚠️  [CRON] Kite token not valid: ${status.reason}. Attempting auto-login...`);
                const loginResult = await kiteAuthService.performAutomatedLogin();

                if (loginResult.success) {
                    console.log('✅ [CRON] Kite auto-login successful! Reconnecting WebSocket...');
                    // Reconnect the Kite WebSocket with the fresh token
                    try { livePriceService._connectToKite(); } catch (_) {}
                } else {
                    console.error('❌ [CRON] Kite auto-login failed:', loginResult.error);
                }
            } catch (error) {
                console.error('❌ [CRON] Error during Kite token refresh:', error.message);
            }
        });
        this.jobs.push(kiteTokenRefresh);

        // ── Settlement prices are now fetched via bhavcopy crons below (no OHLC) ──

        // ── Bhavcopy Settlement Price Fetch ──────────────────────────────
        // NSE: 5:30 PM IST (Mon-Fri) — fetches today's settlement prices
        // MCX: 1:00 AM IST (Tue-Sat) — fetches previous day's settlement prices

        const nseBhavcopyJob = cron.schedule('30 17 * * 1-5', async () => {
            if (PRACTICE) return;
            console.log(`📊 [CRON] Fetching NSE settlement prices (5:30 PM IST)...`);
            try {
                const { fetchAndApplyBhavcopy } = require('./bhavcopyService');
                const result = await fetchAndApplyBhavcopy();
                console.log(`✅ [CRON] Bhavcopy done: NSE=${result.nseMatched}, MCX=${result.mcxMatched}`);
            } catch (error) {
                console.error(`❌ [CRON] Bhavcopy NSE error: ${error.message}`);
            }
            try {
                // NSEIX publishes GIFT NIFTY's own official Daily Settlement
                // Price file mid-afternoon (confirmed real: ~16:16 IST) — well
                // before this 17:30 slot, and it runs on NSE's own trading
                // calendar day. Without this, every open GIFT NIFTY position
                // fails weekly settlement's hasOfficialSettlementAuthority
                // gate (confirmed real: a SettlementRun stuck `blocked` with
                // error "official settlement source unsupported for NSEIX").
                const { fetchAndApplyGiftNiftySettlement } = require('./giftNiftySettlementService');
                await fetchAndApplyGiftNiftySettlement();
                console.log('✅ [CRON] GIFT NIFTY settlement price fetch completed.');
            } catch (error) {
                console.error(`❌ [CRON] GIFT NIFTY settlement error: ${error.message}`);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(nseBhavcopyJob);

        // ── NSE F&O Ban List Sync ─────────────────────────────────────────
        // NSE publishes each trading day's ban list before market open.
        // 8:00 AM IST gives comfortable margin ahead of the 9:15 AM open.
        // Also auto-lifts any previously-banned symbol no longer on today's
        // list — see nseBanListService for the independent nse_banned field.
        const nseBanListJob = cron.schedule('0 8 * * 1-5', async () => {
            if (PRACTICE) return;
            console.log('🚫 [CRON] Syncing NSE F&O ban list...');
            try {
                const { syncNseBanList } = require('./nseBanListService');
                const result = await syncNseBanList();
                console.log(`✅ [CRON] NSE ban list synced: ${result.symbolsInBanList} banned symbols, ${result.bannedCount} instruments newly/still banned, ${result.liftedCount} lifted.`);
            } catch (error) {
                console.error(`❌ [CRON] NSE ban list sync error: ${error.message}`);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(nseBanListJob);

        const mcxBhavcopyJob = cron.schedule('0 1 * * 2-6', async () => {
            if (PRACTICE) return;
            console.log(`📊 [CRON] Fetching MCX settlement prices (1:00 AM IST)...`);
            try {
                const { fetchAndApplyBhavcopy } = require('./bhavcopyService');
                const result = await fetchAndApplyBhavcopy();
                console.log(`✅ [CRON] Bhavcopy done: NSE=${result.nseMatched}, MCX=${result.mcxMatched}`);
            } catch (error) {
                console.error(`❌ [CRON] Bhavcopy MCX error: ${error.message}`);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(mcxBhavcopyJob);

        // ── Atomic Weekend Settlement ───────────────────────────────────
        // Saturday 03:50 IST — after GIFT NIFTY's night session (02:45) and
        // CME's Friday close (02:30 US summer / 03:30 US winter time) so every
        // price is final (settlementService refuses to start a new week
        // earlier) — then hourly retries 04:30-06:30 if a price wasn't ready.
        // The durable period key guarantees that only one worker can commit
        // the week; later invocations are no-ops after success.
        const runWeekendSettlement = async () => {
            console.log('[CRON] Checking Saturday weekly settlement...');
            try {
                const settlementService = require('./settlementService');
                const result = await settlementService.runSettlement({
                    trigger: 'cron',
                    waitForCompletion: true,
                    refreshPrices: true,
                });
                if (result.success) {
                    console.log(`[CRON] Settlement ${result.periodKey}: ${result.alreadyCompleted ? 'already completed' : 'completed successfully'}.`);
                } else {
                    console.error(`[CRON] Settlement ${result.periodKey || 'unknown'} failed: ${result.message}`);
                }
            } catch (error) {
                console.error(`[CRON] Weekend settlement error: ${error.message}`);
            }
        };
        const weekendSettlementJob = cron.schedule('50 3 * * 6', runWeekendSettlement, { timezone: 'Asia/Kolkata' });
        this.jobs.push(weekendSettlementJob);
        const weekendSettlementRetryJob = cron.schedule('30 4-6 * * 6', runWeekendSettlement, { timezone: 'Asia/Kolkata' });
        this.jobs.push(weekendSettlementRetryJob);

        // Recover a run stranded by process restart, network failure, or a crash
        // after DB commit. Recovery uses the run's stored trading date rather
        // than advancing to the current week.
        const settlementRecoveryJob = cron.schedule('*/15 * * * *', async () => {
            try {
                const settlementService = require('./settlementService');
                const result = await settlementService.recoverIncompleteSettlements({ ensureCurrentPeriod: true });
                if (result.recovered) {
                    console.log(`[CRON] Settlement recovery ${result.periodKey || ''}: ${result.message}`);
                }
            } catch (error) {
                console.error(`[CRON] Settlement recovery error: ${error.message}`);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(settlementRecoveryJob);

        // Margin-call block (2 Nov 2026): a block from an earlier settlement
        // week is lifted once the weekly M2M reset has happened
        // (marginBlockReset.js). Every 15 minutes, and once shortly after start.
        const liftMarginBlocks = async () => {
            try {
                const lifted = await require('./marginBlockReset').liftBlocksFromEarlierWeeks();
                if (lifted) console.log(`🔓 [CRON] Margin-call block lifted for ${lifted} account(s) (new settlement week)`);
            } catch (error) {
                console.error(`[CRON] Margin block reset error: ${error.message}`);
            }
        };
        const marginBlockResetJob = cron.schedule('*/15 * * * *', liftMarginBlocks, { timezone: 'Asia/Kolkata' });
        this.jobs.push(marginBlockResetJob);
        setTimeout(liftMarginBlocks, 60 * 1000);

        // Every PM2 worker observes the durable committed generation and rebuilds
        // its own metrics/live-price maps. On-demand risk checks also reconcile,
        // while this poll keeps WebSocket-only clients current.
        const settlementGenerationSyncJob = cron.schedule('*/2 * * * *', async () => {
            try {
                const metricsEngine = require('./metricsEngine');
                await metricsEngine.synchronizeSettlementGeneration({ maxAgeMs: 0, broadcast: true });
            } catch (error) {
                console.error(`[Settlement] Worker generation sync error: ${error.message}`);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(settlementGenerationSyncJob);

        // ── Expiry Auto Square-Off ───────────────────────────────────────
        // 3:46 PM IST (after NSE's real 3:40 PM close + intraday square-off
        // at 3:41 + pending-order cancel at 3:42) + 11:33 PM IST (after MCX's
        // 11:30 PM close, same staggered pattern). Comment previously said
        // 3:35 PM / 11:32 PM — neither matched the actual cron schedule below.
        // autoSquareOffExpiredPositions() itself isn't exchange-scoped (it
        // sweeps every instrument expiring today regardless of exchange), so
        // these two triggers also catch any GLOBAL/COMEX expiry same-day.
        // Checks for instruments that expired today and auto-squares-off open positions
        // 4:00 PM IST, after the NSE futures expiry cut — that cut takes its
        // closing snapshot at 3:55 PM, 15 minutes after the 3:40 close
        // (config/expiryRules.js snapshotDelayMin); this sweep used to run at
        // 3:46 and would have closed those positions before the cut.
        const expirySquareOffNSE = cron.schedule('0 16 * * 1-5', async () => {
            console.log('📊 [CRON] Expiry auto square-off check (NSE close)...');
            try {
                await this.autoSquareOffExpiredPositions({ skipSegments: ['GLOBAL', 'COMEX-FUT'] });
                console.log('✅ [CRON] NSE expiry auto square-off completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during NSE expiry auto square-off:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(expirySquareOffNSE);

        // MCX close + 17 min (after the close + 15 intraday square-off): 11:47 PM
        // IST in US summer time, 00:12 the next day in US winter
        // (isMcxCloseSlot). autoSquareOffExpiredPositions picks "today" by the
        // server's UTC date, which at 00:12 IST is still the expiry day.
        const runMcxExpirySweep = async () => {
            if (!isMcxCloseSlot(CLOSE_SETTLE_MIN + 2)) return;
            console.log('📊 [CRON] Expiry auto square-off check (MCX close)...');
            try {
                await this.autoSquareOffExpiredPositions();
                console.log('✅ [CRON] MCX expiry auto square-off completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during MCX expiry auto square-off:', error);
            }
        };
        const expirySquareOffMCX = cron.schedule('47 23 * * 1-5', runMcxExpirySweep, { timezone: 'Asia/Kolkata' });
        this.jobs.push(expirySquareOffMCX);
        const expirySquareOffMCXAfterMidnight = cron.schedule('12 0 * * 2-6', runMcxExpirySweep, { timezone: 'Asia/Kolkata' });
        this.jobs.push(expirySquareOffMCXAfterMidnight);

        // ── GIFT NIFTY expiry close: 3:31 PM IST ─────────────────────────
        // NSE IX stops the expiring NIFTY contract at 15:30 IST on expiry day
        // (consolidated circular NSEIFSC/TRADE/2129, "Expiry Day - Trade
        // timings 06.15 AM to 3.30 PM"), so open GIFT NIFTY positions close
        // right then at its last bid/ask (giftNiftyFeedService holds the
        // expiring contract's quotes until 16:00) — not with NSE at 3:46 PM.
        const giftExpiryClose = cron.schedule('31 15 * * 1-5', async () => {
            console.log('📊 [CRON] GIFT NIFTY expiry close (NSE IX 3:30 PM stop)...');
            try {
                await this.autoSquareOffExpiredPositions({ onlyExchanges: ['NSEIX'] });
                console.log('✅ [CRON] GIFT NIFTY expiry close completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during GIFT NIFTY expiry close:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(giftExpiryClose);

        // ── Contract expiry rules (config/expiryRules.js) ────────────────
        // Plan refresh every 30 min (and once now) — also closes newly loaded
        // contracts until their open day — then every minute run
        // whatever is due: opens automatically, cuts once admin-confirmed —
        // each just after its market's close, at the closing bid/ask.
        const expiryActionService = require('./expiryActionService');
        if (!PRACTICE) expiryActionService.refreshPlan().catch((e) => console.error('❌ [CRON] Expiry plan refresh failed:', e.message));
        const expiryPlanJob = cron.schedule('*/30 * * * *', async () => {
            if (PRACTICE) return;
            try {
                const { errors } = await expiryActionService.refreshPlan();
                if (errors.length) console.error('❌ [CRON] Expiry plan errors:', JSON.stringify(errors));
            } catch (error) {
                console.error('❌ [CRON] Expiry plan refresh failed:', error.message);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(expiryPlanJob);

        // ── Corporate-action cuts (corporateActionCutService.js) ─────────
        // NSE's split / bonus / rights list read once now and on weekdays at
        // 8:45 AM and 1:45 PM — each becomes a cut in the same schedule,
        // the trading day before its ex-date, run once admin-confirmed.
        const corporateCuts = require('./corporateActionCutService');
        const refreshCorporateCuts = async () => {
            try {
                const { planned, retired } = await corporateCuts.refreshPlan();
                console.log(`🗓️  [CRON] Corporate-action cuts: ${planned} planned${retired ? `, ${retired} withdrawn` : ''}`);
            } catch (error) {
                console.error('❌ [CRON] Corporate-action cuts refresh failed:', error.message);
            }
        };
        if (!PRACTICE) refreshCorporateCuts();
        const corporateCutJob = cron.schedule('45 8,13 * * 1-5', async () => {
            if (PRACTICE) return;
            await refreshCorporateCuts();
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(corporateCutJob);

        let expiryRunBusy = false;
        const expiryRunJob = cron.schedule('* * * * *', async () => {
            if (PRACTICE) return;
            if (expiryRunBusy) return; // a long cut may outlast a minute
            expiryRunBusy = true;
            try {
                await expiryActionService.runDue();
            } catch (error) {
                console.error('❌ [CRON] Expiry actions run failed:', error.message);
            } finally {
                expiryRunBusy = false;
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(expiryRunJob);

        // ── Intraday Square-Off at Market Close ──────────────────────────
        // Squares off positions for users who have intraday_squareoff enabled for the segment.
        // NSE/NFO: 3:55 PM IST — 15 minutes after this platform's own 3:40 PM
        // close (see market_hours.dart), once the closing bid/ask has settled
        // (CLOSE_SETTLE_MIN; was 3:41).
        const intradaySquareOffNSE = cron.schedule('55 15 * * 1-5', async () => {
            console.log('🔄 [CRON] Intraday square-off (NSE/NFO close)...');
            try {
                await this.runIntradaySquareOff(['NFO-FUT', 'NFO-OPT']);
                console.log('✅ [CRON] NSE/NFO intraday square-off completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during NSE intraday square-off:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(intradaySquareOffNSE);

        // MCX: 15 minutes after the close, once the closing bid/ask has
        // settled — 11:45 PM IST in US summer time, 00:10 the next day in US
        // winter (isMcxCloseSlot; was one minute after the close).
        const runMcxIntradaySquareOff = async () => {
            if (!isMcxCloseSlot(CLOSE_SETTLE_MIN)) return;
            console.log('🔄 [CRON] Intraday square-off (MCX close)...');
            try {
                await this.runIntradaySquareOff(['MCX-FUT', 'MCX-OPT']);
                console.log('✅ [CRON] MCX intraday square-off completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during MCX intraday square-off:', error);
            }
        };
        const intradaySquareOffMCX = cron.schedule('45 23 * * 1-5', runMcxIntradaySquareOff, { timezone: 'Asia/Kolkata' });
        this.jobs.push(intradaySquareOffMCX);
        const intradaySquareOffMCXAfterMidnight = cron.schedule('10 0 * * 2-6', runMcxIntradaySquareOff, { timezone: 'Asia/Kolkata' });
        this.jobs.push(intradaySquareOffMCXAfterMidnight);

        // COMEX and GLOBAL index futures (Dow, Nasdaq, S&P, Russell, Nikkei)
        // are CME Globex: Sunday–Friday 5:00 PM – 4:00 PM Chicago time, a
        // daily break 4–5 PM (cmegroup.com contract specs). Scheduled in
        // Chicago time so the close follows US daylight saving by itself —
        // 2:30 AM IST in US summer, 3:30 AM IST in US winter (from 2 Nov 2026).
        // Mon–Fri in Chicago = each session; Friday's 4 PM close is Saturday
        // morning IST. No run while the market is shut over the weekend.
        // COMEX intraday square-off: at the close, 4:00 PM Chicago.
        const intradaySquareOffCOMEX = cron.schedule('0 16 * * 1-5', async () => {
            console.log('🔄 [CRON] Intraday square-off (COMEX close)...');
            try {
                await this.runIntradaySquareOff(['COMEX-FUT']);
                console.log('✅ [CRON] COMEX intraday square-off completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during COMEX intraday square-off:', error);
            }
        }, { timezone: 'America/Chicago' });
        this.jobs.push(intradaySquareOffCOMEX);

        // GLOBAL index futures intraday square-off: at the CME close, 4:00 PM
        // Chicago (see COMEX above). GIFT NIFTY is under the same GLOBAL
        // switch but is NSE IX (closes 2:45 AM IST), so it has its own run.
        const intradaySquareOffGLOBAL = cron.schedule('0 16 * * 1-5', async () => {
            console.log('🔄 [CRON] Intraday square-off (GLOBAL close)...');
            try {
                await this.runIntradaySquareOff(['GLOBAL'], { excludeExchanges: ['NSEIX'] });
                console.log('✅ [CRON] GLOBAL intraday square-off completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during GLOBAL intraday square-off:', error);
            }
        }, { timezone: 'America/Chicago' });
        this.jobs.push(intradaySquareOffGLOBAL);

        // GIFT NIFTY (NSE IX): 2:46 AM IST, one minute after its night
        // session closes at 2:45 (market_hours.dart). GLOBAL switch. Tue–Sat.
        const intradaySquareOffGIFT = cron.schedule('46 2 * * 2-6', async () => {
            console.log('🔄 [CRON] Intraday square-off (GIFT NIFTY close)...');
            try {
                await this.runIntradaySquareOff(['GLOBAL'], { onlyExchanges: ['NSEIX'] });
                console.log('✅ [CRON] GIFT NIFTY intraday square-off completed.');
            } catch (error) {
                console.error('❌ [CRON] Error during GIFT NIFTY intraday square-off:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(intradaySquareOffGIFT);

        // ── NFO closing window: 3:20 PM IST ─────────────────────────────
        // From 3:20 to 3:40 PM only MARKET orders are allowed in NFO-FUT /
        // NFO-OPT (utils/nfoMarketOnlyWindow.js — placeTrade/modifyTrade
        // refuse limit/stop-loss for masters and clients). Every pending NFO
        // LIMIT / SL / SL-M order is cancelled at the start of the window.
        const cancelPendingNFOWindow = cron.schedule('20 15 * * 1-5', async () => {
            console.log('🗑️ [CRON] 3:20 PM NFO market-only window — cancelling pending NFO limit/stop-loss orders...');
            try {
                const { CANCEL_REMARK } = require('../utils/nfoMarketOnlyWindow');
                const count = await this.cancelPendingOrdersBySegment(['NFO-FUT', 'NFO-OPT'], CANCEL_REMARK);
                console.log(`✅ [CRON] Cancelled ${count} pending NFO order(s) for the 3:20-3:40 PM window.`);
            } catch (error) {
                console.error('❌ [CRON] Error cancelling NFO pending orders at 3:20 PM:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(cancelPendingNFOWindow);

        // ── Auto-Cancel Pending Orders at Market Close ───────────────────
        // Cancels all unfilled limit/stop orders once the market closes.
        // Runs 1 minute after intraday square-off to avoid clashing.
        // NFO-FUT, NFO-OPT: 3:42 PM IST
        const cancelPendingNSE = cron.schedule('42 15 * * 1-5', async () => {
            console.log('🗑️ [CRON] Cancelling pending orders (NSE/NFO close)...');
            try {
                const count = await this.cancelPendingOrdersBySegment(['NFO-FUT', 'NFO-OPT']);
                console.log(`✅ [CRON] Cancelled ${count} pending NSE/NFO order(s).`);
            } catch (error) {
                console.error('❌ [CRON] Error cancelling NSE pending orders:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(cancelPendingNSE);

        // MCX-FUT, MCX-OPT: two minutes after the close — 11:32 PM IST in US
        // summer time, 11:57 PM in US winter (isMcxCloseSlot).
        const cancelPendingMCX = cron.schedule('32,57 23 * * 1-5', async () => {
            if (!isMcxCloseSlot(2)) return;
            console.log('🗑️ [CRON] Cancelling pending orders (MCX close)...');
            try {
                const count = await this.cancelPendingOrdersBySegment(['MCX-FUT', 'MCX-OPT']);
                console.log(`✅ [CRON] Cancelled ${count} pending MCX order(s).`);
            } catch (error) {
                console.error('❌ [CRON] Error cancelling MCX pending orders:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(cancelPendingMCX);

        // COMEX-FUT and GLOBAL index futures: 4:02 PM Chicago, Mon–Fri —
        // right after the CME close (2:32 AM IST in US summer, 3:32 AM IST in
        // US winter; Friday's is Saturday morning IST). Never while the
        // market is shut over the weekend.
        const cancelPendingCOMEX = cron.schedule('2 16 * * 1-5', async () => {
            console.log('🗑️ [CRON] Cancelling pending orders (COMEX close)...');
            try {
                const count = await this.cancelPendingOrdersBySegment(['COMEX-FUT']);
                console.log(`✅ [CRON] Cancelled ${count} pending COMEX order(s).`);
            } catch (error) {
                console.error('❌ [CRON] Error cancelling COMEX pending orders:', error);
            }
        }, { timezone: 'America/Chicago' });
        this.jobs.push(cancelPendingCOMEX);

        // GLOBAL index futures — selected by exchange GLOBAL, so GIFT NIFTY
        // (exchange NSEIX, same INDICES segment) is left to its own cancel.
        const cancelPendingGLOBAL = cron.schedule('2 16 * * 1-5', async () => {
            console.log('🗑️ [CRON] Cancelling pending orders (GLOBAL close)...');
            try {
                const count = await this.cancelPendingOrdersForInstruments({ exchange: 'GLOBAL' });
                console.log(`✅ [CRON] Cancelled ${count} pending GLOBAL order(s).`);
            } catch (error) {
                console.error('❌ [CRON] Error cancelling GLOBAL pending orders:', error);
            }
        }, { timezone: 'America/Chicago' });
        this.jobs.push(cancelPendingGLOBAL);

        // GIFT NIFTY (NSE IX): 2:47 AM IST, Tue–Sat — right after the night
        // session ends (2:45 AM) for each Mon–Fri trading day, so a pending
        // GIFT order lives through that trading day's day and night sessions
        // and is cancelled at its close, like every other segment. Selected
        // by exchange, not segment: GIFT's segment (INDICES) is shared with
        // the GLOBAL index futures, which close at the CME time (above).
        const cancelPendingGIFT = cron.schedule('47 2 * * 2-6', async () => {
            console.log('🗑️ [CRON] Cancelling pending orders (GIFT NIFTY night-session close)...');
            try {
                const count = await this.cancelPendingOrdersForInstruments({ exchange: 'NSEIX' });
                console.log(`✅ [CRON] Cancelled ${count} pending GIFT NIFTY order(s).`);
            } catch (error) {
                console.error('❌ [CRON] Error cancelling GIFT NIFTY pending orders:', error);
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(cancelPendingGIFT);

        // ── Special sessions (utils/specialSessions.js — Sunday 8 Nov 2026
        // Diwali Muhurat trading) ── every weekend minute, run what the session
        // calendar has due: the snapshot of the week settled before it (instead
        // of 23:55), the NFO 3:20 PM market-only cancel, and intraday
        // square-off / pending-order cancel one and two minutes after each
        // window's close — the same jobs a weekday runs at its close.
        const specialSessionJobs = cron.schedule('* * * * 0,6', async () => {
            const jobs = require('../utils/specialSessions').dueJobs(new Date());
            for (const job of jobs) {
                if (job.type === 'weekSnapshot') {
                    console.log('📒 [CRON] Special session: snapshotting the week settled before it...');
                    try {
                        await snapshotWeeklySummary();
                    } catch (error) {
                        console.error('❌ [CRON] Special session weekly summary snapshot failed:', error);
                    }
                    try {
                        await snapshotWeeklyLedger();
                    } catch (error) {
                        console.error('❌ [CRON] Special session weekly ledger snapshot failed:', error);
                    }
                    continue;
                }
                try {
                    if (job.type === 'marketOnlyCancel') {
                        const { CANCEL_REMARK } = require('../utils/nfoMarketOnlyWindow');
                        const count = await this.cancelPendingOrdersBySegment(job.segments, CANCEL_REMARK);
                        console.log(`✅ [CRON] Special session ${job.window}: cancelled ${count} pending NFO limit/stop-loss order(s) for the market-only window.`);
                    } else if (job.type === 'squareoff') {
                        console.log(`🔄 [CRON] Special session ${job.window} close: intraday square-off...`);
                        await this.runIntradaySquareOff(job.segments);
                        console.log(`✅ [CRON] Special session ${job.window} intraday square-off completed.`);
                    } else if (job.type === 'cancel') {
                        const count = await this.cancelPendingOrdersBySegment(job.segments);
                        console.log(`✅ [CRON] Special session ${job.window} close: cancelled ${count} pending order(s).`);
                    }
                } catch (error) {
                    console.error(`❌ [CRON] Special session ${job.window} ${job.type} failed:`, error);
                }
            }
        }, { timezone: 'Asia/Kolkata' });
        this.jobs.push(specialSessionJobs);

        // Weekend carry-forward is handled by settlementService.js (durable,
        // transactional). The old weekendCarryForwardService module was removed.

        const engineMode = redisService.isAvailable()
            ? 'Redis + BullMQ (cron fallback standby)'
            : 'DB polling every 10s (Redis unavailable)';

        console.log(`✅ Cron Scheduler activated (limit engine: ${engineMode}).`);
    }

    /**
     * Run intraday square-off for the given segments.
     * Finds all users who have intraday_squareoff enabled for any of the segments,
     * then squares off their open positions in those segments using bid/ask CMP.
     */
    async runIntradaySquareOff(segments, options = {}) {
        const Trade = require('../models/Trade');
        const metricsEngine = require('./metricsEngine');
        const { _squareOffUserSegments } = require('../controllers/masterUserController');

        // Find all users who have intraday_squareoff enabled for any of these segments.
        // GLOBAL may be stored under its legacy name INDICES.
        const segmentNames = segments.map(s => s.toUpperCase());
        if (segmentNames.includes('GLOBAL') && !segmentNames.includes('INDICES')) segmentNames.push('INDICES');
        const users = await User.find({
            deleted_at: null,
            intraday_squareoff: {
                $elemMatch: { enabled: true, exchange_name: { $in: segmentNames } },
            },
        }).select('_id username intraday_squareoff').lean();

        if (users.length === 0) {
            console.log(`   No users with intraday square-off enabled for ${segments.join(', ')}.`);
            return;
        }

        console.log(`   Found ${users.length} user(s) with intraday square-off enabled.`);

        // At EOD, real deployments can have thousands of users squaring off
        // simultaneously — this previously ran one full user (its own
        // transaction(s) inside _squareOffUserSegments) at a time, so the
        // job could run long past market close, and a user squared off late
        // reads a staler bid/ask than one squared off early. Each user's
        // square-off already acquires its own independent lease (see
        // masterUserController.js's _squareOffUserSegments), so running
        // several users concurrently doesn't introduce new lock contention
        // beyond what already happens if two crons ever overlapped.
        const INTRADAY_SQUAREOFF_CONCURRENCY = 10;
        let totalSquaredOff = 0;

        const eligibleUsers = users
            .map(u => ({
                user: u,
                userEnabledSegments: (u.intraday_squareoff || [])
                    .filter(s => s.enabled && segmentNames.includes(s.exchange_name.toUpperCase()))
                    .map(s => s.exchange_name),
            }))
            .filter(e => e.userEnabledSegments.length > 0);

        for (let i = 0; i < eligibleUsers.length; i += INTRADAY_SQUAREOFF_CONCURRENCY) {
            const chunk = eligibleUsers.slice(i, i + INTRADAY_SQUAREOFF_CONCURRENCY);
            await Promise.all(chunk.map(async ({ user: u, userEnabledSegments }) => {
                try {
                    const count = await _squareOffUserSegments(u._id.toString(), userEnabledSegments, options);
                    if (count > 0) {
                        totalSquaredOff += count;
                        console.log(`   ✅ ${u.username}: squared off ${count} position(s) in ${userEnabledSegments.join(', ')}`);
                    }
                } catch (e) {
                    console.error(`   ❌ ${u.username}: square-off error: ${e.message}`);
                }
            }));
        }

        console.log(`   ✅ Total: ${totalSquaredOff} position(s) squared off for ${users.length} user(s).`);
    }

    /**
     * Cancel all pending (unfilled) limit/stop orders for instruments in the given segments.
     * Called at market close to clean up stale orders that won't fill until next day.
     * Returns the number of orders cancelled.
     */
    async cancelPendingOrdersBySegment(segments, remark = 'Auto-cancelled: market closed') {
        const segmentsUpper = segments.map(s => s.toUpperCase());
        return this.cancelPendingOrdersForInstruments({ segment: { $in: segmentsUpper } }, remark);
    }

    /** Cancels every pending order on the active instruments matching `instrumentMatch` (e.g. { exchange: 'NSEIX' }). */
    async cancelPendingOrdersForInstruments(instrumentMatch, remark = 'Auto-cancelled: market closed') {
        const Trade = require('../models/Trade');
        const KiteInstrument = require('../models/KiteInstrument');
        const orderBookService = require('./orderBookService');
        const redisService = require('./redisService');

        // Get all instrument tokens matching the filter
        const instruments = await KiteInstrument.find({
            ...instrumentMatch,
            is_active: true,
            deleted_at: null,
        }).select('instrument_token').lean();

        const tokens = instruments.map(i => i.instrument_token.toString());
        if (tokens.length === 0) return 0;

        // Find and cancel all pending orders for these instruments
        const pendingOrders = await Trade.find({
            status: 'pending',
            instrument_token: { $in: tokens },
            deleted_at: null,
        }).select('_id instrument_token transaction_type order_type trigger_direction').lean();

        if (pendingOrders.length === 0) return 0;

        const ids = pendingOrders.map(o => o._id);
        await Trade.updateMany(
            { _id: { $in: ids }, status: 'pending', deleted_at: null },
            { $set: { status: 'cancelled', remarks: remark } }
        );

        // Remove from Redis order book if available. Each removal is
        // independent (different order ids, no shared session/lease) —
        // previously ran fully sequentially, one Redis round trip at a time,
        // for however many thousand pending orders exist at market close.
        if (redisService.isAvailable()) {
            const REDIS_CLEANUP_CONCURRENCY = 20;
            for (let i = 0; i < pendingOrders.length; i += REDIS_CLEANUP_CONCURRENCY) {
                const chunk = pendingOrders.slice(i, i + REDIS_CLEANUP_CONCURRENCY);
                await Promise.all(chunk.map(async (order) => {
                    try {
                        await orderBookService.removeOrder(
                            order._id.toString(),
                            order.instrument_token.toString(),
                            order.transaction_type,
                            order.order_type,
                            order.trigger_direction
                        );
                    } catch (_) {}
                }));
            }
        }

        return pendingOrders.length;
    }

    /**
     * Resets the `balance` field to equal the `credits` field for all users and masters
     */
    async resetWeeklyBalances() {
        // 1. Reset Master Balances
        const masterUpdateResult = await Master.updateMany({}, [
            { $set: { equity: '$credits' } }
        ]);
        console.log(`📊 [CRON] Reset balances for ${masterUpdateResult.modifiedCount} Masters.`);

        // 2. Reset User Balances
        const userUpdateResult = await User.updateMany({}, [
            { $set: { equity: '$credits' } }
        ]);
        console.log(`📊 [CRON] Reset balances for ${userUpdateResult.modifiedCount} Users.`);
    }

    /**
     * Expiry-day safety net: closes every position still open on an
     * instrument expiring today, at the closing bid/ask (a long sells at the
     * bid, a short buys at the ask; LTP when that side has no quote). The
     * admin-confirmed early cuts (expiryActionService.js) normally leave
     * nothing for this to do — it catches anything unconfirmed or unruled.
     *
     * @param {object} [options]
     * @param {Date} [options.now]
     * @param {string[]} [options.skipSegments] - e.g. GLOBAL/COMEX on the 3:46 PM
     *   run: on their expiry day those still trade for hours after NSE's close.
     * @param {string[]} [options.onlyExchanges] - e.g. ['NSEIX'] for the 3:31 PM
     *   GIFT NIFTY run, right after NSE IX stops the expiring contract.
     */
    async autoSquareOffExpiredPositions(options = {}) {
        const KiteInstrument = require('../models/KiteInstrument');
        const metricsEngine = require('./metricsEngine');
        const { closeOpenPositions, bidAskPrice } = require('./positionCloseService');
        let lease = null;

        try {
            lease = await beginTradeWrite('expiry_square_off');
            const today = options.now ? new Date(options.now) : new Date();
            today.setHours(0, 0, 0, 0);
            const tomorrow = new Date(today);
            tomorrow.setDate(tomorrow.getDate() + 1);

            const filter = { expiry: { $gte: today, $lt: tomorrow }, deleted_at: null };
            if (options.skipSegments?.length) filter.segment = { $nin: options.skipSegments };
            if (options.onlyExchanges?.length) filter.exchange = { $in: options.onlyExchanges };
            const expiredInstruments = await KiteInstrument.find(filter)
                .select('instrument_token tradingsymbol exchange last_price segment').lean();

            if (expiredInstruments.length === 0) {
                console.log('   No instruments expiring today.');
                return;
            }

            const quotes = new Map();
            for (const instrument of expiredInstruments) {
                const token = instrument.instrument_token.toString();
                quotes.set(token, {
                    bid: metricsEngine._bidMap?.get(token),
                    ask: metricsEngine._askMap?.get(token),
                    ltp: metricsEngine._ltpMap?.get(token) || instrument.last_price,
                });
            }

            const result = await closeOpenPositions({
                instruments: expiredInstruments,
                priceFor: (token, closeSide) => bidAskPrice(quotes.get(token), closeSide),
                lease,
                trade: {
                    placed_by: 'SYSTEM',
                    trade_type: 'margin_square_off',
                    remarks: (symbol) => `Auto square-off: instrument expired (${symbol})`,
                },
                reason: 'EXPIRY_SQUARE_OFF',
                txSuffix: 'EXP',
                faultInjector: options.faultInjector,
            });

            if (result.openPositions === 0) {
                console.log(`   ${expiredInstruments.length} instrument(s) expiring today, no open positions.`);
                return;
            }
            console.log(`   ✅ Auto squared off ${result.squared} of ${result.openPositions} position(s).`);
        } finally {
            await lease?.release();
        }
    }
}

module.exports = new CronService();
