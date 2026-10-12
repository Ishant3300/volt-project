#!/usr/bin/env bash
# One-time Telegram setup — run it yourself on the server:
#   cd ~/stocker-backend-node && bash scripts/watchdog/setup-telegram.sh
# 1. Asks for the bot token from @BotFather (typed hidden, never printed).
# 2. You send any message in the alert group (with the bot added); the script
#    finds that group's chat id.
# 3. Saves TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID to .env, sends a test message
#    and restarts only the watchdog (not the trading backend).
set -eu
cd "$(dirname "$0")/../.."
ENV_FILE=".env"
read -rsp "Paste the bot token from @BotFather (hidden), then Enter: " TOKEN; echo
TOKEN="$(printf '%s' "$TOKEN" | tr -d '\r\n ')"
if ! curl -sf "https://api.telegram.org/bot${TOKEN}/getMe" >/dev/null; then echo "That token was not accepted by Telegram. Nothing saved."; exit 1; fi
echo "Token OK. Now open your alert group in Telegram (bot already added) and send any message, e.g. 'hi'."
read -rp "Press Enter after sending it... " _
CHATS="$(curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates" | python3 -c '
import sys, json
seen = {}
for u in json.load(sys.stdin).get("result", []):
    m = u.get("message") or u.get("my_chat_member") or u.get("channel_post") or {}
    c = m.get("chat") or {}
    if c.get("id") is not None:
        seen[c["id"]] = c.get("title") or c.get("username") or c.get("first_name") or ""
for i, t in seen.items():
    print(f"{i}\t{t}")
')"
if [ -z "$CHATS" ]; then echo "No message found. In BotFather run /setprivacy -> Disable for this bot, send a message in the group, then run this again."; exit 1; fi
echo "Chats the bot can see:"; echo "$CHATS" | nl -w2 -s') '
read -rp "Number of the alert chat: " N
CHAT_ID="$(echo "$CHATS" | sed -n "${N}p" | cut -f1)"
[ -n "$CHAT_ID" ] || { echo "Invalid choice. Nothing saved."; exit 1; }
cp "$ENV_FILE" "$ENV_FILE.bak-telegram-$(date +%s)"
grep -v '^TELEGRAM_BOT_TOKEN=\|^TELEGRAM_CHAT_ID=' "$ENV_FILE" > "$ENV_FILE.tmp" || true
printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "$TOKEN" "$CHAT_ID" >> "$ENV_FILE.tmp"
mv "$ENV_FILE.tmp" "$ENV_FILE"; chmod 600 "$ENV_FILE"
node scripts/watchdog/notify.js --text "Apex/Volt alerts connected. You will get server, error and login alerts here."
pm2 restart health-watchdog --update-env >/dev/null 2>&1 || true
echo "Done. A test message was sent to the chat."
