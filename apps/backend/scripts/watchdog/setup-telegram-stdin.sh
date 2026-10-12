#!/usr/bin/env bash
# Telegram setup without typing in a terminal: the bot token arrives on stdin
# (from SETUP-TELEGRAM.ps1's Windows box on the user's PC — never shown or
# logged). Then it waits up to 3 minutes for a message in the alert group
# (send /start there), saves TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID to .env,
# sends a test message and restarts only the watchdog.
set -eu
cd "$(dirname "$0")/../.."
IFS= read -r TOKEN || true
TOKEN="$(printf '%s' "$TOKEN" | tr -d '\r\n ')"
[ -n "$TOKEN" ] || { echo "No token received. Nothing changed."; exit 1; }
if ! curl -sf "https://api.telegram.org/bot${TOKEN}/getMe" >/dev/null; then
  echo "Telegram did not accept that token (revoked or mistyped?). Nothing changed."; exit 1
fi
echo "Token OK. Now send /start in your Telegram alert group (bot already added). Waiting up to 3 minutes..."
CHAT=""
for _ in $(seq 1 36); do
  CHAT="$(curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates" | python3 -c '
import sys, json
best = None
for u in json.load(sys.stdin).get("result", []):
    m = u.get("message") or u.get("my_chat_member") or {}
    c = m.get("chat") or {}
    if c.get("type") in ("group", "supergroup"):
        best = (u["update_id"], c["id"], c.get("title") or "")
if best:
    print(f"{best[1]}\t{best[2]}")
')"
  [ -n "$CHAT" ] && break
  sleep 5
done
[ -n "$CHAT" ] || { echo "No group message seen in 3 minutes. Add the bot to the group, send /start there, and run this again. Nothing changed."; exit 1; }
CHAT_ID="$(printf '%s' "$CHAT" | cut -f1)"
echo "Found group: $(printf '%s' "$CHAT" | cut -f2)"
cp .env ".env.bak-telegram-$(date +%s)"
grep -v '^TELEGRAM_BOT_TOKEN=\|^TELEGRAM_CHAT_ID=' .env > .env.tmp || true
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "$TOKEN" "$CHAT_ID" >> .env.tmp
mv .env.tmp .env; chmod 600 .env
node scripts/watchdog/notify.js --text "Apex/Volt alerts connected. You will get server, error and login alerts here."
pm2 restart health-watchdog --update-env >/dev/null 2>&1 || true
echo "Done. A test message was sent to the group."
