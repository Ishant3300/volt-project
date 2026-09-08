/**
 * Discrete permission keys a Super Admin can grant to a regular Admin.
 *
 * A regular Admin's baseline (reads, dashboards, everything not listed
 * here) stays available regardless of permissions — these keys gate only
 * the specific write/sensitive actions called out in the architecture plan.
 * Super Admin bypasses every one of these checks unconditionally (see
 * requireAdminPermission.js) — this list only restricts regular Admins.
 */
const ADMIN_PERMISSION_KEYS = Object.freeze([
  'TRADE_CUSTOM', // Custom/arbitrary-price order placement
  'TRADE_DELETE', // Delete a trade (tradeController.deleteTrade)
  'WALLET_MANAGE', // Wallet assign/withdraw (walletController)
  'BROKERAGE_MANAGE', // Brokerage-settings CRUD, for any master (adminController)
  'INSTRUMENT_MANAGE', // Instrument enable/disable/delete/restore (adminRoutes)
  'SETTLEMENT_TRIGGER', // Manually trigger settlement (settlementController.startSettlement)
  'FRESH_STOPLOSS_MANAGE', // Fresh-stoploss-limit CRUD
  'REPORTS_ACCESS', // Report generation/access endpoints
  'MASTER_EDIT_ANY', // Write access to any master's profile/limits/permissions (reads stay open to every admin)
  'QUANTITY_MANAGE', // Grouped-quantity and script-quantity CRUD (adminController/groupedQuantityController)
]);

module.exports = { ADMIN_PERMISSION_KEYS };
