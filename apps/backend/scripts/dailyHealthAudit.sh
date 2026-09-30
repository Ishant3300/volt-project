#!/usr/bin/env bash
# READ-ONLY daily health audit. Run by pm2 (daily-audit-am / -mid / -pm) on
# trading days at 8:45 AM, 12:30 PM and 4:15 PM IST (pm2 cron in server UTC:
# 03:15, 07:00, 10:45); writes ~/audit/<IST date>_<HHMM>.txt and
# keeps 45 days. Changes nothing on the system — only reads process state,
# logs, the database and Redis (via scripts/healthAudit.js).
set -u
APP="$HOME/stocker-backend-node"
OUTDIR="$HOME/audit"
mkdir -p "$OUTDIR"
STAMP="$(TZ=Asia/Kolkata date +%Y-%m-%d_%H%M)"
REPORT="$OUTDIR/$STAMP.txt"
D="$(date -u +%Y-%m-%d)"

{
  echo "== Daily health audit — $(TZ=Asia/Kolkata date '+%a %d %b %Y %H:%M IST')"
  echo "--- server / backend"
  pm2 jlist 2>/dev/null | python3 -c '
import sys, json, time
for p in json.load(sys.stdin):
    if p["name"] != "stocker-backend-node":
        continue
    e = p["pm2_env"]
    st = "OK   " if e["status"] == "online" else "FAIL "
    up = round((time.time() * 1000 - e["pm_uptime"]) / 3600000, 1)
    print("%s backend %s | up %s h | restarts %s | mem %s MB | cpu %s%%" % (st, e["status"], up, e["restart_time"], round(p["monit"]["memory"] / 1e6), p["monit"]["cpu"]))
'
  code="$(curl -s -o /dev/null -m 10 -w '%{http_code}' https://apexlive-api.mynpe.in/)"
  if [ "$code" = "200" ]; then echo "OK    live API responding (200)"; else echo "FAIL  live API returned $code"; fi
  df -h / | tail -1 | awk '{ print ($5+0 < 85 ? "OK   " : "WARN ") " disk " $5 " used (" $4 " free)" }'
  free -m | awk '/Mem/ { print ($7 > 500 ? "OK   " : "WARN ") " RAM available " $7 " MB of " $2 }'

  L="$(pm2 jlist | python3 -c 'import sys,json; print([p for p in json.load(sys.stdin) if p["name"]=="stocker-backend-node"][0]["pm2_env"]["pm_out_log_path"])')"
  E="$(pm2 jlist | python3 -c 'import sys,json; print([p for p in json.load(sys.stdin) if p["name"]=="stocker-backend-node"][0]["pm2_env"]["pm_err_log_path"])')"
  echo "--- feeds / logs (today)"
  last_tick_line="$(grep -h "PriceQueue\|NEAR-MISS\|order(s) to execute" "$L" | tail -1 | cut -c1-19)"
  echo "INFO  last price-queue activity: ${last_tick_line:-none}"
  echo "INFO  Kite feed reconnect/close events today: $(grep "$D" "$L" | grep -ciE 'Kite WebSocket closed|Kite.*reconnect')"
  echo "INFO  GIFT feed warnings today (pre-open 5:30-7:00 AM IST is normal): $(grep -h "$D" "$E" "$L" 2>/dev/null | grep -cE 'GiftNiftyFeed.*(stale|Poll failed|No NIFTY)')"
  stale="$(grep -h "$D" "$E" "$L" 2>/dev/null | grep -c 'STALE TICK SKIPPED')"
  if [ "$stale" -gt 0 ]; then echo "WARN  stale ticks skipped for order matching today: $stale"; else echo "OK    no stale ticks skipped for order matching"; fi
  echo "INFO  last order audit: $(grep 'OrderAudit' "$L" | tail -1 | sed 's/^.*\] //' | cut -c1-90)"
  healed="$(grep "$D" "$L" | grep -ci 'orphan')"
  if [ "$healed" -gt 0 ]; then echo "WARN  order-book orphans found/healed today: $healed"; else echo "OK    no order-book orphans today"; fi
  errs="$(grep "$D" "$E" | grep -viE 'MONGOOSE\] Warning|trace-warnings|ALLOWED_ORIGINS|MarketCalendar|GiftNiftyFeed|MassiveFeed|^\s*at |node_modules' | grep -cE 'Error|error|❌')"
  if [ "$errs" -gt 0 ]; then
    echo "WARN  error lines today (excluding known warnings): $errs — most frequent:"
    grep "$D" "$E" | grep -viE 'MONGOOSE\] Warning|trace-warnings|ALLOWED_ORIGINS|MarketCalendar|GiftNiftyFeed|MassiveFeed|^\s*at |node_modules' | grep -E 'Error|error|❌' | sed -E 's/^[0-9T:-]+: //' | cut -c1-120 | sort | uniq -c | sort -rn | head -5 | sed 's/^/        /'
  else
    echo "OK    no unexpected errors in today's error log"
  fi

  echo "--- data"
  cd "$APP" && timeout 120 node scripts/healthAudit.js 2>&1 | grep -v 'MONGOOSE\|trace-warnings'

  echo "--- summary"
} > "$REPORT" 2>&1

FAILS="$(grep -c '^FAIL' "$REPORT")"
WARNS="$(grep -c '^WARN' "$REPORT")"
if [ "$FAILS" -gt 0 ]; then echo "RESULT: $FAILS FAIL, $WARNS WARN — needs attention" >> "$REPORT";
elif [ "$WARNS" -gt 0 ]; then echo "RESULT: all running; $WARNS warning(s) to look at" >> "$REPORT";
else echo "RESULT: everything running smoothly" >> "$REPORT"; fi

ln -sf "$REPORT" "$OUTDIR/latest.txt"
find "$OUTDIR" -name '20*.txt' -mtime +45 -delete 2>/dev/null
tail -1 "$REPORT"
