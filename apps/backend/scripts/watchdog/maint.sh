#!/usr/bin/env bash
# Planned restart / deploy: silence the watchdog's restart, API, 5xx and
# database alerts for N minutes (default 10) and tell the Telegram chat.
#   scripts/watchdog/maint.sh 10      scripts/watchdog/maint.sh off
set -u
DIR="$HOME/watchdog"; mkdir -p "$DIR"
cd "$(dirname "$0")/../.." || exit 1
if [ "${1:-}" = "off" ]; then
  rm -f "$DIR/maintenance-until"
  node scripts/watchdog/notify.js --text "Maintenance finished — all alerts on again." >/dev/null 2>&1 || true
  echo "maintenance off"; exit 0
fi
MIN="${1:-10}"
echo $(( $(date +%s%3N) + MIN * 60000 )) > "$DIR/maintenance-until"
node scripts/watchdog/notify.js --text "Planned maintenance for ${MIN} min — restart/API/database alerts paused." >/dev/null 2>&1 || true
echo "maintenance for ${MIN} min"
