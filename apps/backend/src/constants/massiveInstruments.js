/**
 * Which KiteInstrument records are actually fed by Massive.com.
 *
 * The index futures (ES/NQ/YM/RTY/NKD) deliberately share the platform's
 * existing 'GLOBAL' segment/exchange with everything else non-NSE/MCX/COMEX
 * (GIFT Nifty, legacy instruments), so segment/exchange alone can't identify
 * "which GLOBAL instruments does Massive feed" — name is the unambiguous key
 * for those. COMEX (GC/SI/HG) has its own dedicated segment, no ambiguity.
 *
 * Shared by scripts/seedGlobalFutures.js, massiveFuturesFeedService.js, and
 * massiveSettlementService.js so the instrument list can't drift between them.
 */

const GLOBAL_INDEX_NAMES = ['ES', 'NQ', 'YM', 'RTY', 'NKD'];
const COMEX_METAL_SEGMENT = 'COMEX-FUT';

module.exports = { GLOBAL_INDEX_NAMES, COMEX_METAL_SEGMENT };
