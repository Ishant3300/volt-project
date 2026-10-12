#!/usr/bin/env bash
# Telegram setup without typing in a terminal: the bot token arrives on stdin
# (from SETUP-TELEGRAM.ps1's Windows box on the user's PC — never shown or
# logged). Then it waits up to 3 minutes for a message in the alert group
# (send /start there), saves TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID to .env,
# sends a test message and restarts only the watchdog.
set -eu
cd "$(dirname "$0")/../.."
LOG="$HOME/watchdog/setup.log"; mkdir -p "$HOME/watchdog"
log() { echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }
log "setup started"
IFS= read -r TOKEN || true
TOKEN="$(printf '%s' "$TOKEN" | tr -d '\r\n ')"
log "token received: ${#TOKEN} characters, shape $(printf %s "$TOKEN" | sed -E 's/[0-9]/9/g; s/[A-Za-z_-]/a/g' | tr -s a9 | head -c 10)"
[ -n "$TOKEN" ] || { log "no token"; echo "No token received. Nothing changed."; exit 1; }
if ! curl -sf "https://api.telegram.org/bot${TOKEN}/getMe" >/dev/null; then
  log "token rejected by Telegram"; echo "Telegram did not accept that token (revoked or mistyped?). Nothing changed."; exit 1
fi
echo "Token OK. Now send /start to the bot (in your private chat with it, or in a group with it). Waiting up to 3 minutes..."
CHAT=""
for _ in $(seq 1 36); do
  CHAT="$(curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates" | python3 -c '
import sys, json
group = private = None
for u in json.load(sys.stdin).get("result", []):
    m = u.get("message") or u.get("my_chat_member") or {}
    c = m.get("chat") or {}
    if c.get("type") in ("group", "supergroup"):
        group = (c["id"], c.get("title") or "group")
    elif c.get("type") == "private":
        private = (c["id"], "private chat with " + (c.get("first_name") or c.get("username") or "you"))
best = group or private
if best:
    print(f"{best[0]}\t{best[1]}")
')"
  [ -n "$CHAT" ] && break
  sleep 5
done
[ -n "$CHAT" ] || { log "no chat message within 3 min"; echo "No message seen in 3 minutes. Send /start to the bot (group or private chat) and run this again. Nothing changed."; exit 1; }
CHAT_ID="$(printf '%s' "$CHAT" | cut -f1)"
log "chat found: $(printf '%s' "$CHAT" | cut -f2)"
echo "Found: $(printf '%s' "$CHAT" | cut -f2)"
cp .env ".env.bak-telegram-$(date +%s)"
grep -v '^TELEGRAM_BOT_TOKEN=\|^TELEGRAM_CHAT_ID=' .env > .env.tmp || true
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "$TOKEN" "$CHAT_ID" >> .env.tmp
mv .env.tmp .env; chmod 600 .env
node scripts/watchdog/notify.js --text "Apex/Volt alerts connected. You will get server, error and login alerts here."
pm2 restart health-watchdog --update-env >/dev/null 2>&1 || true
log "saved and test message sent"
echo "Done. A test message was sent."
