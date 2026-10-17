# Practice (paper) trading — separate system

Self-signup practice accounts ("Create practice account" on the app / web login).
No real money: balances are **tokens** (amount chosen at sign-up), prices are
**simulated** (not real market prices) and change **every 30 minutes**, no
brokerage, and brokerage / bills / ledger / settlement / wallet transfers /
investor login are hidden. Same app, same screens otherwise.

## Hard rules

1. **The live backend is never changed or slowed.** Practice runs the same code
   from its own folder (`~/practice-backend`) as its own pm2 process
   (`practice-backend`, nice +10, max_memory_restart 500M), its own MongoDB
   database (`stocker_practice`), its own Redis DB index and its own
   `JWT_SECRET`. Live deploys never include practice files; practice is
   deployed separately.
2. **Practice has no market data connection at all**: no Kite (WebSocket,
   REST, login, token refresh), no live price stream, no NSE IX / Massive /
   bhavcopy / ban-list fetches. Kite issues one session per API key, so a
   practice Kite login would log *live* out — practice never logs in.
3. **Every practice price is simulated** (`services/practice/simPrice.js`):
   display, live P&L, market-order fills, pending-order matching,
   square-offs, quotes, option chain, depth, charts and settlement.

## Simulated prices

- Each contract has an **anchor** `{price, slot}`; slots are 30-minute steps
  of the IST clock. The price at slot `s` is a deterministic random walk from
  the anchor: `anchor × exp(σ · Σ z(token, i))` for `i` in `(anchor.slot, s]`,
  `z` a seeded normal from `(token, i)` — the same for every process and
  restart, so charts, fills and P&L always agree.
- Prices move only during the contract's market session; outside it the price
  holds at the last in-session slot.
- First anchor = the contract's last official close (copied once from live).
  After that the walk is self-contained; anchors are rolled forward nightly so
  sums stay short. Settlement and expiry use the simulated price.
- Bid / ask = price ∓ one tick (rounded to the contract's tick size).

## Switch

`PRACTICE_MODE=1` (see `src/config/practice.js`). With it unset every code path
is byte-for-byte the live behaviour.
