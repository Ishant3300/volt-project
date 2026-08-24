# MCX Segment Naming Fix - Complete ✅

## Problem Statement
When creating brokerage/margin/quantity settings for MCX instruments, they were being saved with `exchange_name: "MCX"` instead of the proper segment name like `"MCX-OPT"` or `"MCX-FUT"`. This caused issues with data organization and retrieval.

## Solution Implemented

### Backend Changes ✅
All create methods in `adminController.js` use the **upsert pattern** to prevent duplicates:

1. **createBrokerageSettings** (Line ~930)
   ```javascript
   await BrokerageSettings.findOneAndUpdate(
     { type, exchange_name, script_name, deleted_at: null },
     { type, exchange_name, script_name, brk_value, deleted_at: null },
     { upsert: true, new: true, setDefaultsOnInsert: true }
   );
   ```

2. **createScriptQuantity** (Line ~650)
   ```javascript
   await ScriptQuantity.findOneAndUpdate(
     { exchange_name, script_name, deleted_at: null },
     { exchange_name, script_name, lot_size, max_qty, brk_qty, deleted_at: null },
     { upsert: true, new: true, setDefaultsOnInsert: true }
   );
   ```

3. **createTradeMargin** (Line ~750)
   ```javascript
   await TradeMargin.findOneAndUpdate(
     { exchange_name, script_name, amount_type, deleted_at: null },
     { exchange_name, script_name, amount_type, trade_margin, deleted_at: null },
     { upsert: true, new: true, setDefaultsOnInsert: true }
   );
   ```

4. **createGroupedQuantity** (Line ~420)
   ```javascript
   await GroupedQuantity.findOneAndUpdate(
     { exchange_name, lot_name, instrument_symbol, deleted_at: null },
     { exchange_name, lot_name, instrument_id, instrument_symbol, max_qty, break_qty, lot_size, deleted_at: null },
     { upsert: true, new: true, setDefaultsOnInsert: true }
   );
   ```

**How Upsert Works:**
- If a document matching the filter exists → **UPDATE** it with new values
- If no document matches → **CREATE** a new one
- Result: No duplicates, always up-to-date data

### Frontend Changes ✅

All four create views now use **segment name** for MCX instruments instead of exchange name:

#### 1. create_brokerage_view.dart (Lines 213-218)
```dart
// Use segment for MCX instruments (MCX-FUT, MCX-OPT), otherwise use exchange
final exchangeName = inst.segment.isNotEmpty &&
        (inst.segment.toUpperCase() == 'MCX-FUT' ||
            inst.segment.toUpperCase() == 'MCX-OPT')
    ? inst.segment
    : inst.exchange;
```

#### 2. create_trade_margin_view.dart (Lines 213-218)
```dart
// Use segment for MCX instruments (MCX-FUT, MCX-OPT), otherwise use exchange
final exchangeName = inst.segment.isNotEmpty &&
        (inst.segment.toUpperCase() == 'MCX-FUT' ||
            inst.segment.toUpperCase() == 'MCX-OPT')
    ? inst.segment
    : inst.exchange;
```

#### 3. create_script_quantity_view.dart (Lines 203-208)
```dart
// Use segment for MCX instruments (MCX-FUT, MCX-OPT), otherwise use exchange
final exchangeName = _selected!.segment.isNotEmpty &&
        (_selected!.segment.toUpperCase() == 'MCX-FUT' ||
            _selected!.segment.toUpperCase() == 'MCX-OPT')
    ? _selected!.segment
    : _selected!.exchange;
```

#### 4. add_instrument_to_lot_view.dart (Lines 330-336)
```dart
// Determine exchange name (use segment for MCX instruments)
final instrumentExchange = _selectedInstrument?.exchange ?? widget.exchange;
final instrumentSegment = _selectedInstrument?.segment ?? '';
final exchangeName = instrumentSegment.isNotEmpty &&
        (instrumentSegment.toUpperCase() == 'MCX-FUT' ||
            instrumentSegment.toUpperCase() == 'MCX-OPT')
    ? instrumentSegment
    : instrumentExchange;
```

## How It Works

### Before Fix:
```
MCX Gold Futures → exchange_name: "MCX" ❌
MCX Gold Options → exchange_name: "MCX" ❌
```

### After Fix:
```
MCX Gold Futures → exchange_name: "MCX-FUT" ✅
MCX Gold Options → exchange_name: "MCX-OPT" ✅
```

### Duplicate Handling:
```
User creates: GOLDM25FEB FUT with brokerage 20
Database: Creates new entry

User creates: GOLDM25FEB FUT with brokerage 25 (duplicate)
Database: Updates existing entry to brokerage 25 (no duplicate created)
```

## Testing Checklist

### Test Duplicate Prevention:
1. ✅ Create brokerage for GOLDM25FEB (MCX-FUT) with value 20
2. ✅ Try creating same instrument again with value 25
3. ✅ Verify: Only one entry exists with value 25 (updated, not duplicated)

### Test Segment Naming:
1. ✅ Create settings for MCX-FUT instrument
2. ✅ Verify database has `exchange_name: "MCX-FUT"` (not "MCX")
3. ✅ Create settings for MCX-OPT instrument
4. ✅ Verify database has `exchange_name: "MCX-OPT"` (not "MCX")

### Test Other Exchanges:
1. ✅ Create settings for NFO-FUT instrument
2. ✅ Verify database has `exchange_name: "NFO"` (correct)
3. ✅ Create settings for NFO-OPT instrument
4. ✅ Verify database has `exchange_name: "NFO"` (correct)

## Benefits

1. **Proper Data Organization**: MCX instruments are now categorized by segment (MCX-FUT, MCX-OPT)
2. **No Duplicates**: Upsert pattern ensures only one entry per instrument
3. **Easy Updates**: Re-submitting same instrument updates values instead of creating duplicates
4. **Consistent Behavior**: All four create views follow the same pattern
5. **Backward Compatible**: Non-MCX instruments continue to use exchange name

## Files Modified

### Backend:
- `stocker-backend-node/src/controllers/adminController.js`
  - All create methods already use upsert pattern (no changes needed)

### Frontend:
- `stocker/lib/views/create_brokerage_view.dart` ✅
- `stocker/lib/views/create_trade_margin_view.dart` ✅
- `stocker/lib/views/create_script_quantity_view.dart` ✅
- `stocker/lib/views/add_instrument_to_lot_view.dart` ✅

## Status: COMPLETE ✅

All changes have been implemented and verified. The system now:
- Uses correct segment names for MCX instruments
- Prevents duplicate entries through upsert pattern
- Maintains data consistency across all create operations
