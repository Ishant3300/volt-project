# Quick Start Guide: Option Chain & Market Depth

## Prerequisites
- Backend server running
- MongoDB connected
- Kite authentication completed
- Instruments fetched
- Flutter app installed

## Step-by-Step Testing

### 1. Backend Setup (5 minutes)

```bash
# Start backend
cd stocker-backend-node
npm run dev

# In another terminal, run tests
node test/testNewAPIs.js
```

**Expected Output:**
```
✅ Login successful
✅ Instrument search working
✅ Option chain fetched
✅ Market depth fetched
```

### 2. Kite Authentication (2 minutes)

```bash
# Open browser
http://localhost:3000/api/kite/login

# Complete login flow
# Check backend logs for success
```

**Expected Log:**
```
✅ Connected to Kite WebSocket
📊 Subscribing to tokens
```

### 3. Flutter App (3 minutes)

```bash
cd stocker
flutter run
```

**Test Flow:**
1. Login with your credentials
2. View watchlist (should show instruments)
3. Tap any instrument card

### 4. Test Trade Card Page (2 minutes)

**What to Check:**
- ✅ Instrument name displays correctly
- ✅ Live price updates (watch for changes)
- ✅ Change percentage shows with color
- ✅ OHLC stats display (Open, High, Low, Close)
- ✅ "Option Chain" link visible
- ✅ "Market Depth" link visible

### 5. Test Option Chain (3 minutes)

**Steps:**
1. Tap "Option Chain" link
2. Wait for data to load

**What to Check:**
- ✅ Option chain displays with strikes
- ✅ CE (Call) prices on left
- ✅ PE (Put) prices on right
- ✅ Strike prices in center
- ✅ Filter buttons work:
  - Tap "All" - shows all expiries
  - Tap "7 Days" - filters to 7 days
  - Tap "1 Month" - filters to 1 month
  - Tap "3 Months" - filters to 3 months

**Test Search:**
1. Type "BANKNIFTY" in search box
2. Tap send icon
3. Option chain should update

### 6. Test Market Depth (2 minutes)

**Steps:**
1. Go back to Trade Card
2. Tap "Market Depth" link
3. Bottom sheet should open

**What to Check:**
- ✅ OHLC data displays
  - Open price
  - High price
  - Low price
  - Close price
- ✅ Last price shows
- ✅ Close button works

### 7. Test Live Updates (5 minutes)

**Steps:**
1. Keep Trade Card page open
2. Watch the header price
3. Watch OHLC stats

**What to Check:**
- ✅ Prices update automatically
- ✅ Change percentage updates
- ✅ Color changes (green/red)
- ✅ No manual refresh needed

## Common Issues & Quick Fixes

### Issue 1: Option Chain Shows "No data"
```bash
# Fix: Fetch instruments
curl -X POST http://localhost:3000/api/kite/instruments/fetch \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Issue 2: Market Depth Fails
```bash
# Fix: Check Kite auth
curl http://localhost:3000/api/kite/auth-status
```

### Issue 3: Live Prices Not Updating
```bash
# Fix: Check WebSocket in backend logs
# Should see: "✅ Connected to Kite WebSocket"
```

### Issue 4: Search Not Working
```bash
# Fix: Verify instruments in database
curl http://localhost:3000/api/kite/instruments/info \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Quick Test Commands

### Test Option Chain API
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/kite/option-chain/NIFTY
```

### Test Market Depth API
```bash
# Replace 12345 with actual instrument token
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/kite/market-depth/12345
```

### Test Search API
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/kite/instruments/search?q=RELIANCE&limit=5"
```

## Success Criteria

### Backend
- [ ] All tests pass in testNewAPIs.js
- [ ] Option chain API returns data
- [ ] Market depth API returns data
- [ ] WebSocket connected
- [ ] No errors in logs

### Frontend
- [ ] App launches without errors
- [ ] Watchlist displays instruments
- [ ] Trade card shows live data
- [ ] Option chain loads and displays
- [ ] Filters work correctly
- [ ] Search changes instrument
- [ ] Market depth shows OHLC
- [ ] Live prices update automatically

## Performance Benchmarks

### Expected Response Times
- Option Chain: < 500ms
- Market Depth: < 300ms
- Search: < 200ms
- Live Price Update: < 100ms

### Expected Behavior
- Smooth scrolling in option chain
- No lag when switching filters
- Instant search results
- Real-time price updates

## Troubleshooting Checklist

If something doesn't work:

1. **Check Backend Logs**
   ```bash
   # Look for errors in terminal
   ```

2. **Check Flutter Logs**
   ```bash
   # Look for errors in debug console
   ```

3. **Verify Authentication**
   ```bash
   curl http://localhost:3000/api/kite/auth-status
   ```

4. **Check Database**
   ```bash
   # Ensure MongoDB is running
   # Ensure instruments are fetched
   ```

5. **Restart Services**
   ```bash
   # Restart backend
   # Hot reload Flutter app
   ```

## Next Steps After Testing

1. **Add More Instruments to Watchlist**
   - Test with different symbols
   - Verify option chains for each

2. **Monitor Performance**
   - Check response times
   - Monitor memory usage
   - Watch for any lag

3. **Test Edge Cases**
   - Instruments with no options
   - Very long option chains
   - Network interruptions

4. **Gather Feedback**
   - Note any UI/UX issues
   - Identify missing features
   - Plan improvements

## Support

If you encounter issues:
1. Check logs (backend and frontend)
2. Review IMPLEMENTATION_SUMMARY.md
3. Read OPTION_CHAIN_AND_MARKET_DEPTH.md
4. Run test suite: `node test/testNewAPIs.js`

## Estimated Total Testing Time: 20-25 minutes

Happy Testing! 🚀
