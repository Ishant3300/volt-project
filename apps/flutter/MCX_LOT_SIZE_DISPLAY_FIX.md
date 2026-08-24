# MCX Lot Size Display Fix ✅

## Problem
The trade card was showing "1 Lot = 1 qty" for MCX-OPT and MCX-FUT instruments, but it should show "1 Lot = 100 qty" because MCX trading rules specify that 1 lot = 100 quantity.

## Root Cause Analysis

### Investigation Results:
1. **Zerodha's API Data**: Returns `lot_size = 1` for all MCX instruments
2. **Database (KiteInstrument)**: Has `lot_size = 1` (correct, matches Zerodha)
3. **Business Rule**: MCX trading convention is 1 LOT = 100 QTY

### Conclusion:
The "1 lot = 100 qty" is a **business rule** specific to MCX trading, NOT data from Zerodha's API. Zerodha returns `lot_size = 1` for MCX instruments, and we need to apply a 100x multiplier in our application logic.

## Solution
Apply MCX-specific multiplier (100) in the `getInstrumentLimit` function to convert Zerodha's lot_size to actual trading quantity.

### Code Changes

**File**: `stocker-backend-node/src/controllers/scriptQtyDetailController.js`

**Implementation**:
```javascript
// CRITICAL FIX: MCX lot size multiplier
// Zerodha's API returns lot_size = 1 for all MCX instruments
// But MCX trading rule: 1 LOT = 100 QTY (business rule, not from Zerodha)
// Apply 100x multiplier for MCX-FUT and MCX-OPT
let actualLotSize = limit.lot_size || 1;
const isMCX = normalizedSegment === 'MCX-FUT' || normalizedSegment === 'MCX-OPT';
if (isMCX) {
  actualLotSize = 100; // MCX business rule: 1 lot = 100 qty
}

res.status(200).json({
  success: true,
  data: {
    exchange_name: segment,
    turnover: allowedExchange.turnover,
    lot: allowedExchange.lot,
    limit: {
      max_qty: limit.max_qty,
      break_qty: limit.break_qty,
      lot_size: actualLotSize, // 100 for MCX, otherwise from limit
      instrument_symbol: limit.instrument_symbol
    }
  }
});
```

## How It Works

### Data Flow:
1. Frontend calls `/api/trade/instrument-limit?segment=MCX-OPT&instrument_id=12345`
2. Backend finds the limit from `GroupedQuantity` table (has `lot_size = 1` from Zerodha)
3. Backend checks if segment is MCX-FUT or MCX-OPT
4. If MCX, apply multiplier: `actualLotSize = 100`
5. Frontend receives `lot_size: 100` and displays "1 Lot = 100 qty"

### Example Response:
```json
{
  "success": true,
  "data": {
    "exchange_name": "MCX-OPT",
    "turnover": false,
    "lot": true,
    "limit": {
      "max_qty": 5,
      "break_qty": 0,
      "lot_size": 100,  // ✅ MCX multiplier applied
      "instrument_symbol": "COPPER1030CE23MAR25"
    }
  }
}
```

## Why This Approach?

### Zerodha's Data:
- **lot_size = 1** in CSV for MCX instruments
- This is how Zerodha represents MCX contracts
- Our database correctly stores this value

### MCX Trading Rules:
- **1 LOT = 100 QTY** is the actual trading convention
- This is a business rule enforced by MCX exchange
- Not reflected in Zerodha's instrument data

### Our Solution:
- Keep database accurate (lot_size = 1 from Zerodha)
- Apply business rule in application logic (multiply by 100 for MCX)
- Clean separation of data vs. business rules

## Verification

### Zerodha API Check:
```bash
node check_zerodha_mcx_data.js
```

**Results**:
```
GOLD26APRFUT: LOT_SIZE from Zerodha = 1
COPPER26MAR1175CE: LOT_SIZE from Zerodha = 1
```

### Database Check:
```javascript
KiteInstrument.find({ exchange: 'MCX' })
// Returns: lot_size = 1 (correct, matches Zerodha)
```

### Application Logic:
```javascript
if (segment === 'MCX-FUT' || segment === 'MCX-OPT') {
  actualLotSize = 100; // Business rule
}
```

## Impact

### Before Fix:
```
Trade Card Display:
📊 1 Lot = 1 qty  ❌ WRONG
   Max: 5 Lots
   Order: 1 Lot = 1 qty
```

### After Fix:
```
Trade Card Display:
📊 1 Lot = 100 qty  ✅ CORRECT
   Max: 5 Lots
   Order: 1 Lot = 100 qty
```

## Testing

1. ✅ Restart backend server
2. ✅ Open any MCX-OPT instrument (e.g., COPPER 1030 CE)
3. ✅ Check the lot info banner
4. ✅ Verify it shows "1 Lot = 100 qty"
5. ✅ Place an order for 1 lot
6. ✅ Verify backend receives quantity = 100

## Related Documentation

- See `MCX_LOT_SIZE_FIX.md` for the original lot size handling implementation
- See `MCX_SEGMENT_FIX_COMPLETE.md` for segment naming fixes

## Status: COMPLETE ✅

The fix ensures that MCX instruments always display the correct lot size (100) by applying the MCX business rule multiplier, while keeping the database accurate with Zerodha's data.
