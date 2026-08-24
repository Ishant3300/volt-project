#!/bin/bash
# SSH to production and check Redis logs/status
# Usage: pnpm logs:redis:prod
set -e

EC2_HOST="13.204.61.199"
EC2_USER="ec2-user"
SSH_KEY="/Users/devarshukani/Work/Keys/apex/my-ec2-key"

echo "📡 Connecting to $EC2_HOST — checking Redis logs..."
ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" '
  RCLI=$(which redis-cli 2>/dev/null || which redis6-cli 2>/dev/null || echo "")
  if [ -z "$RCLI" ]; then
    echo "⚠️  redis-cli not found on server"
    exit 1
  fi

  echo "=== Redis PING ==="
  $RCLI ping

  # Check if Redis log file is configured
  LOGFILE=$($RCLI CONFIG GET logfile 2>/dev/null | tail -1)
  if [ -n "$LOGFILE" ] && [ "$LOGFILE" != "" ] && [ -f "$LOGFILE" ]; then
    echo ""
    echo "=== $LOGFILE (last 100 lines) ==="
    tail -100 "$LOGFILE"
  elif sudo journalctl -u redis6 --no-pager -n 1 &>/dev/null; then
    echo ""
    echo "=== systemd journal for redis6 (last 100 lines) ==="
    sudo journalctl -u redis6 --no-pager -n 100
  else
    echo ""
    echo "=== Redis INFO (no log file configured) ==="
    $RCLI info server | grep -E "redis_version|uptime|tcp_port|config_file"
    $RCLI info memory | grep -E "used_memory_human|maxmemory_human"
    $RCLI info clients | grep -E "connected_clients"
    echo ""
    echo "No persistent log file configured."
    echo "For real-time monitoring: ssh in and run: redis6-cli MONITOR"
  fi
'
