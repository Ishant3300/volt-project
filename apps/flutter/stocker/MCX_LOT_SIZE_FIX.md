# MCX Lot Size Fix - March 18, 2026

## Issue
MCX instruments (MCX-FUT and MCX-OPT) have a lot size of 100, meaning:
- 1 LOT = 100 QTY
- When a user buys 1 lot, they are actually buying 100 quantity

The system was not properly handling this conversion in:
1. Backend lot limit validation
2. Backend brokerage calculation  
3. Frontend display in orders and history pages

## Changes Made

### 1. Backend: `stocker-backend-node/src/controllers/tradeController.js`

#### A. Lot Size Fetching (Line ~140)
**Before:** Only checked GroupedQuantity and ScriptQuantity for lot_size
**After:** Now prioritizes KiteInstrument.lot_size (most accurate source), then falls back to GroupedQuantity/ScriptQuantity

```javascript
// First, try to get lot_size from KiteInstrument (most accurate)
const kiteInst = await KiteInstrument.findOne({ instrument_token });
if (kiteInst && kiteInst.lot_size) {
    lotSize = kiteInst.lot_size;
}
```

**Impact:** Ensures MCX instruments correctly use lot_size = 100 for margin calculations

#### B. Brokerage Calculation (Line ~410)
**Before:** Only checked ScriptQuantity for lot_size
**After:** Now checks KiteInstrument first, then ScriptQuantity

```javascript
let lotSizeForBrokerage = 1;
const kiteInstForBrk = await KiteInstrument.findOne({ instrument_token });
if (kiteInstForBrk && kiteInstForBrk.lot_size) {
    lotSizeForBrokerage = kiteInstForBrk.lot_size;
} else {
    const lotSizeDoc = await ScriptQuantity.findOne({ ... });
    lotSizeForBrokerage = lotSizeDoc?.lot_size || 1;
}
const lots = quantity / lotSizeForBrokerage;
brokerage = lots * brokerageRule.brk_value;
```

**Impact:** Correct brokerage calculation for MCX trades (e.g., 100 qty = 1 lot)

### 2. Frontend: `stocker/lib/models/trade.dart`

#### Updated `isLotBased` Getter
**Before:** Comment mentioned "MCX is always lots" but didn't explicitly mention MCX-OPT
**After:** Clarified that both MCX-FUT and MCX-OPT use lots with lot_size = 100

```dart
/// True when this trade should be displayed in lots instead of raw quantity.
/// MCX is always lots (MCX-FUT, MCX-OPT). NFO-FUT is lots.
/// Turnover-mode instruments (NSEIX, GLOBAL, NFO equity FUTs) use quantity.
bool get isLotBased {
  final seg = segment.toUpperCase();
  if (seg.isNotEmpty) {
    // Prefer segment (most reliable)
    // MCX-FUT and MCX-OPT both use lots (lot_size = 100 for MCX)
    return seg == 'MCX-FUT' || seg == 'MCX-OPT' || seg == 'NFO-FUT';
  }
  // Fallback heuristic if segment isn't populated
  final ex = exchange.toUpperCase();
  // All MCX instruments (both FUT and OPT) use lots
  if (ex == 'MCX') return true;
  if (ex == 'NFO') {
    final sym = tradingSymbol.toUpperCase();
    return sym.endsWith('FUT');
  }
  return false;
}
```

**Impact:** Trade model correctly identifies MCX-OPT as lot-based

### 3. Frontend: `stocker/lib/pages/orders_page.dart`

#### Updated `_positionVolumeLabel` Function
**Before:** Checked for MCX-FUT and MCX-OPT but comment wasn't clear
**After:** Added explicit comment about MCX lot_size = 100

```dart
/// Volume label for a position: "+X LOTS" or "+X QTY".
String _positionVolumeLabel(String exchange, String tradingsymbol, int quantity,
    {bool showPrefix = false, String segment = '', int lotSize = 1}) {
  final ex = exchange.toUpperCase();
  final sym = tradingsymbol.toUpperCase();
  final seg = segment.toUpperCase();

  bool isLot = false;
  if (seg.isNotEmpty) {
    // MCX-FUT and MCX-OPT both use lots (lot_size = 100 for MCX)
    isLot = seg == 'MCX-FUT' || seg == 'MCX-OPT' || seg == 'NFO-FUT';
  } else if (ex == 'MCX') {
    // All MCX instruments use lots
    isLot = true;
  } else if (ex == 'NFO') {
    isLot = sym.endsWith('FUT');
  }
  
  // ... rest of function converts quantity to lots
}
```

**Impact:** Orders page correctly displays MCX positions in lots

### 4. Frontend: `stocker/lib/pages/history_page.dart`

**No changes needed** - Already uses Trade model's built-in `displayVolume` and `volumeUnit` properties, which automatically handle the conversion.

## Testing Checklist

### Backend Testing
- [ ] Place MCX-FUT buy order with quantity = 100 (should be treated as 1 lot)
- [ ] Place MCX-OPT buy order with quantity = 100 (should be treated as 1 lot)
- [ ] Verify margin calculation uses lot_size = 100 for MCX
- [ ] Verify brokerage calculation uses lot_size = 100 for MCX (if LOT WISE)
- [ ] Verify lot limit validation works correctly (e.g., max 5 lots = max 500 qty)

### Frontend Testing
- [ ] Orders page shows MCX-FUT position as "1 LOT" when quantity = 100
- [ ] Orders page shows MCX-OPT position as "1 LOT" when quantity = 100
- [ ] History page shows MCX-FUT trade as "1 LOT" when quantity = 100
- [ ] History page shows MCX-OPT trade as "1 LOT" when quantity = 100
- [ ] Master view aggregates MCX positions correctly in lots
- [ ] Admin view shows MCX positions correctly in lots

## Example Scenarios

### Scenario 1: User buys 1 lot of MCX GOLD
- **User Action:** Select MCX GOLD, enter 1 LOT
- **Frontend Sends:** quantity = 100 (1 lot × 100)
- **Backend Validates:** Checks if user can afford 1 lot (margin for 100 qty)
- **Backend Stores:** quantity = 100
- **Frontend Displays:** "1 LOT" (100 qty ÷ 100 lot_size)

### Scenario 2: User buys 2 lots of MCX SILVER
- **User Action:** Select MCX SILVER, enter 2 LOTS
- **Frontend Sends:** quantity = 200 (2 lots × 100)
- **Backend Validates:** Checks if user can afford 2 lots (margin for 200 qty)
- **Backend Stores:** quantity = 200
- **Frontend Displays:** "2 LOT" (200 qty ÷ 100 lot_size)

### Scenario 3: Brokerage Calculation (LOT WISE)
- **Trade:** MCX GOLD, quantity = 300 (3 lots)
- **Brokerage Rule:** ₹20 per lot
- **Calculation:** 300 qty ÷ 100 lot_size = 3 lots → 3 × ₹20 = ₹60
- **Result:** ₹60 brokerage charged

## Data Flow

```
User Input (Frontend)
  ↓
1 LOT
  ↓
Convert to Quantity (Frontend)
  ↓
100 QTY
  ↓
Send to Backend
  ↓
Backend Validation (uses lot_size = 100)
  ↓
Store in DB (quantity = 100)
  ↓
Fetch from DB (quantity = 100, lot_size = 100)
  ↓
Display on Frontend (100 ÷ 100 = 1 LOT)
```

## Notes

1. **KiteInstrument is the source of truth** for lot_size
2. **MCX lot_size = 100** for both MCX-FUT and MCX-OPT
3. **NFO-FUT lot_size varies** by instrument (e.g., NIFTY = 50, BANKNIFTY = 15)
4. **Backend stores raw quantity** (not lots)
5. **Frontend converts to lots** for display only

## Related Files

### Backend
- `stocker-backend-node/src/controllers/tradeController.js` - Trade placement and validation
- `stocker-backend-node/src/models/KiteInstrument.js` - Instrument data with lot_size
- `stocker-backend-node/src/models/ScriptQuantity.js` - Script quantity limits
- `stocker-backend-node/src/models/GroupedQuantity.js` - Group-specific quantity limits

### Frontend
- `stocker/lib/models/trade.dart` - Trade model with lot conversion logic
- `stocker/lib/pages/orders_page.dart` - Orders page display
- `stocker/lib/pages/history_page.dart` - History page display
- `stocker/lib/views/trade_card_view.dart` - Trade entry form

---

**Status:** ✅ Complete
**Date:** March 18, 2026
**Developer:** Development Team
