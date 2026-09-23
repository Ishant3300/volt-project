const Trade = require('../models/Trade');
const WeeklySummary = require('../models/WeeklySummary');
const User = require('../models/User');
const Master = require('../models/Master');
const Admin = require('../models/Admin');

/**
 * Snapshots weekly P&L for all users/masters/admins into WeeklySummary collection.
 * Designed to run every Sunday before balance reset.
 */
async function snapshotWeeklySummary() {
  // Week boundaries: Monday 00:00 → Sunday 23:59:59.999
  const now = new Date();
  const dayOfWeek = now.getDay(); // 0=Sun
  const diffToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;

  const weekStart = new Date(now);
  weekStart.setDate(now.getDate() - diffToMonday);
  weekStart.setHours(0, 0, 0, 0);

  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekEnd.getDate() + 6);
  weekEnd.setHours(23, 59, 59, 999);

  console.log(`📊 [WEEKLY] Snapshotting ${weekStart.toISOString()} → ${weekEnd.toISOString()}`);

  // Aggregate completed trades for this week per user_id
  const tradeAgg = await Trade.aggregate([
    {
      $match: {
        status: 'completed',
        deleted_at: null,
        executed_at: { $gte: weekStart, $lte: weekEnd },
      }
    },
    {
      $group: {
        _id: '$user_id',
        pnl: { $sum: '$pnl' },
        brokerage: { $sum: '$brokerage' },
        total_trades: { $sum: 1 },
        buy_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', 0] } },
        sell_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, '$executed_quantity', 0] } },
        turnover: { $sum: { $multiply: ['$executed_price', '$executed_quantity'] } },
        master_id: { $first: '$master_id' },
        admin_id: { $first: '$admin_id' },
      }
    }
  ]);

  // Build a userId → user info map for all roles
  const [users, masters, admins] = await Promise.all([
    User.find({ deleted_at: null }).select('_id username name master_id admin_id').lean(),
    Master.find({ deleted_at: null }).select('_id username name admin_id').lean(),
    Admin.find({ deleted_at: null }).select('_id username name').lean(),
  ]);

  const userMap = {};
  for (const u of users) userMap[u._id.toString()] = { ...u, userModel: 'User' };
  for (const m of masters) userMap[m._id.toString()] = { ...m, userModel: 'Master' };
  for (const a of admins) userMap[a._id.toString()] = { ...a, userModel: 'Admin' };

  // Upsert trade aggregations (these are User-role trades since trade.user_id = User)
  const bulkOps = [];
  for (const row of tradeAgg) {
    const uid = row._id.toString();
    const info = userMap[uid] || {};
    bulkOps.push({
      updateOne: {
        filter: { userId: row._id, week_start: weekStart },
        update: {
          $set: {
            userModel: info.userModel || 'User',
            username: info.username || 'unknown',
            name: info.name || null,
            master_id: row.master_id || info.master_id || null,
            admin_id: row.admin_id || info.admin_id || null,
            week_end: weekEnd,
            pnl: row.pnl,
            brokerage: row.brokerage,
            total_trades: row.total_trades,
            buy_qty: row.buy_qty,
            sell_qty: row.sell_qty,
            turnover: row.turnover,
          }
        },
        upsert: true,
      }
    });
  }

  // Also create zero-entry records for users with no trades this week
  const tradedUserIds = new Set(tradeAgg.map(r => r._id.toString()));
  for (const u of users) {
    if (!tradedUserIds.has(u._id.toString())) {
      bulkOps.push({
        updateOne: {
          filter: { userId: u._id, week_start: weekStart },
          update: {
            $set: {
              userModel: 'User',
              username: u.username,
              name: u.name || null,
              master_id: u.master_id || null,
              admin_id: u.admin_id || null,
              week_end: weekEnd,
              pnl: 0, brokerage: 0, total_trades: 0,
              buy_qty: 0, sell_qty: 0, turnover: 0,
            }
          },
          upsert: true,
        }
      });
    }
  }

  if (bulkOps.length > 0) {
    const result = await WeeklySummary.bulkWrite(bulkOps);
    console.log(`✅ [WEEKLY] Upserted ${result.upsertedCount} new, modified ${result.modifiedCount} existing summaries`);
  } else {
    console.log('ℹ️  [WEEKLY] No users/trades to snapshot');
  }

  return { total: bulkOps.length };
}

/**
 * Snapshots this week's Total P&L into the permanent Ledger column
 * (User.ledger_balance / Master.ledger_balance + an immutable LedgerEntry
 * audit row per owner per week). Designed to run every Sunday 23:55, right
 * alongside snapshotWeeklySummary() and before the Monday balance reset —
 * called separately from cronService.js so a failure here can never affect
 * that existing snapshot.
 *
 * Deliberately recomputes Total P&L from Trade + metricsEngine directly,
 * using the exact formula already live in weeklyAdminController.js's
 * `_getUserEntryBatched`/`_getAggregatedEntryBatched` (total_pnl =
 * -(grossPnl + floatingPnl), a plain sum with no sharing/ceiling math) —
 * rather than calling into that controller — so this feature can never
 * touch its cascade/brokerage-sharing formulas.
 */
async function snapshotWeeklyLedger() {
  const LedgerEntry = require('../models/LedgerEntry');
  const metricsEngine = require('./metricsEngine');

  const now = new Date();
  const dayOfWeek = now.getDay();
  const diffToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;

  const weekStart = new Date(now);
  weekStart.setDate(now.getDate() - diffToMonday);
  weekStart.setHours(0, 0, 0, 0);

  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekEnd.getDate() + 6);
  weekEnd.setHours(23, 59, 59, 999);

  console.log(`📒 [LEDGER] Snapshotting ${weekStart.toISOString()} → ${weekEnd.toISOString()}`);

  const tradeAgg = await Trade.aggregate([
    {
      $match: {
        status: 'completed',
        deleted_at: null,
        executed_at: { $gte: weekStart, $lte: weekEnd },
      }
    },
    { $group: { _id: '$user_id', grossPnl: { $sum: '$pnl' } } },
  ]);

  const users = await User.find({ deleted_at: null }).select('_id master_id').lean();
  const masters = await Master.find({ deleted_at: null }).select('_id master_id').lean();
  const masterById = new Map(masters.map((m) => [m._id.toString(), m]));

  const grossPnlByUser = new Map(tradeAgg.map((r) => [r._id.toString(), r.grossPnl || 0]));

  // Per-user Total P&L, same formula/sign as the live report column.
  const userTotalPnl = new Map();
  for (const u of users) {
    const uid = u._id.toString();
    const grossPnl = grossPnlByUser.get(uid) || 0;
    const floatingPnl = metricsEngine.getCachedMetrics(uid)?.position_pnl || 0;
    userTotalPnl.set(uid, -(grossPnl + floatingPnl));
  }

  // Every master a user reports to, direct + all ancestors up the chain.
  const ancestorMasterIds = (directMasterId) => {
    const chain = [];
    let cur = directMasterId ? directMasterId.toString() : null;
    const seen = new Set();
    while (cur && !seen.has(cur)) {
      seen.add(cur);
      chain.push(cur);
      cur = masterById.get(cur)?.master_id?.toString() || null;
    }
    return chain;
  };

  // Aggregate each master's Total P&L across their ENTIRE downline (all
  // descendant users, however many tiers deep) — matches how the live
  // report's master row already aggregates (plain sum, no per-tier split).
  const masterTotalPnl = new Map();
  for (const u of users) {
    const pnl = userTotalPnl.get(u._id.toString()) || 0;
    for (const mid of ancestorMasterIds(u.master_id)) {
      masterTotalPnl.set(mid, (masterTotalPnl.get(mid) || 0) + pnl);
    }
  }
  // Masters with no users anywhere in their downline still get a zero entry.
  for (const m of masters) {
    const mid = m._id.toString();
    if (!masterTotalPnl.has(mid)) masterTotalPnl.set(mid, 0);
  }

  let written = 0, skipped = 0;

  const applyEntry = async (ownerId, ownerType, totalPnl, Model) => {
    const exists = await LedgerEntry.findOne({ owner_id: ownerId, week_start: weekStart }).select('_id').lean();
    if (exists) { skipped += 1; return; }

    const updated = await Model.findByIdAndUpdate(
      ownerId,
      { $inc: { ledger_balance: totalPnl } },
      { new: true }
    ).select('ledger_balance').lean();
    if (!updated) return;

    try {
      await LedgerEntry.create({
        owner_id: ownerId,
        owner_type: ownerType,
        week_start: weekStart,
        week_end: weekEnd,
        total_pnl_this_week: totalPnl,
        running_balance_after: updated.ledger_balance,
      });
      written += 1;
    } catch (err) {
      // Unique-index race (two overlapping runs) — undo the increment we
      // just applied so a duplicate run can never double-count.
      await Model.findByIdAndUpdate(ownerId, { $inc: { ledger_balance: -totalPnl } });
      console.error(`⚠️  [LEDGER] Duplicate entry for ${ownerType} ${ownerId}, increment reverted:`, err.message);
    }
  };

  for (const u of users) {
    await applyEntry(u._id, 'User', userTotalPnl.get(u._id.toString()) || 0, User);
  }
  for (const m of masters) {
    await applyEntry(m._id, 'Master', masterTotalPnl.get(m._id.toString()) || 0, Master);
  }

  console.log(`✅ [LEDGER] Wrote ${written} entries, skipped ${skipped} already-snapshotted`);
  return { written, skipped };
}

module.exports = { snapshotWeeklySummary, snapshotWeeklyLedger };
