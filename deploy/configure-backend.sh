#!/bin/bash
# ============================================================================
# One-time (idempotent) provisioning of a FRESH EC2 box for the Apex backend.
#
# Target: Amazon Linux 2023, c6i.large (2 vCPU / 4 GB) + 50 GB gp3, ap-south-1
# Host:   13.207.113.128  (apexlive-api.mynpe.in)
#
# What it installs / configures on the REMOTE server:
#   - Node.js 20 LTS + git
#   - Local Redis 6, bound to 127.0.0.1, with maxmemory + noeviction so a
#     BullMQ backlog can never fill the disk and crash the box
#   - PM2 process manager + pm2-logrotate (caps app logs so they can't grow
#     unbounded — the classic "disk full -> crash" cause)
#   - Chromium system libraries required by puppeteer/playwright (Kite auto-login)
#   - nginx reverse proxy (80/443 -> 127.0.0.1:3000) with WebSocket upgrade for
#     /ws/live-prices
#   - certbot + Let's Encrypt TLS for apexlive-api.mynpe.in
#   - 2 GB swap file as an OOM safety net for the hourly Chromium spike
#   - journald disk cap
#
# Run from your Mac:   bash deploy/configure-backend.sh
# Safe to re-run: every step checks state before acting.
# ============================================================================
set -euo pipefail

# ── Connection ──────────────────────────────────────────────────────────────
EC2_HOST="13.207.113.128"
EC2_USER="ec2-user"
SSH_KEY="/Users/devarshukani/Work/Keys/apex/apex-backend-prod.pem"

# ── App / domain ─────────────────────────────────────────────────────────────
DOMAIN="apexlive-api.mynpe.in"
CERTBOT_EMAIL="devarsh@indi.technology"   # Let's Encrypt renewal notices
APP_PORT="3000"                    # backend PORT (matches .env / BASE_URL)
REMOTE_DIR="/home/ec2-user/stocker-backend-node"
PM2_APP="stocker-backend-node"

# ── Resource caps ────────────────────────────────────────────────────────────
REDIS_MAXMEMORY="1gb"              # hard cap on local Redis
SWAP_SIZE_MB="2048"                # 2 GB swap
PM2_LOG_MAX_SIZE="100M"            # per-file cap before rotation
PM2_LOG_RETAIN="7"                 # keep 7 rotated files
JOURNALD_MAX="200M"                # cap systemd journal on disk

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"

if [ ! -f "$SSH_KEY" ]; then
  echo "❌ SSH key not found at $SSH_KEY"
  exit 1
fi
chmod 400 "$SSH_KEY" 2>/dev/null || true

echo "🔧 Provisioning $EC2_HOST ($DOMAIN)..."
echo "   This is idempotent — safe to re-run."
echo ""

# The whole remote provisioning runs in one SSH session. Variables from the
# local shell are expanded here (double-quoted heredoc), so the values above
# are baked into the remote script.
ssh -i "$SSH_KEY" $SSH_OPTS "${EC2_USER}@${EC2_HOST}" "bash -s" <<REMOTE
set -euo pipefail

DOMAIN="$DOMAIN"
CERTBOT_EMAIL="$CERTBOT_EMAIL"
APP_PORT="$APP_PORT"
REMOTE_DIR="$REMOTE_DIR"
PM2_APP="$PM2_APP"
REDIS_MAXMEMORY="$REDIS_MAXMEMORY"
SWAP_SIZE_MB="$SWAP_SIZE_MB"
PM2_LOG_MAX_SIZE="$PM2_LOG_MAX_SIZE"
PM2_LOG_RETAIN="$PM2_LOG_RETAIN"
JOURNALD_MAX="$JOURNALD_MAX"

echo "════════════════════════════════════════════════════════"
echo " 1/9  System packages"
echo "════════════════════════════════════════════════════════"
sudo dnf update -y -q
sudo dnf install -y -q git tar gzip which

echo "════════════════════════════════════════════════════════"
echo " 2/9  Node.js 20 LTS"
echo "════════════════════════════════════════════════════════"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
  sudo dnf install -y nodejs
else
  echo "   node already installed: \$(node -v)"
fi
echo "   node \$(node -v), npm \$(npm -v)"

echo "════════════════════════════════════════════════════════"
echo " 3/9  Redis (local, capped)"
echo "════════════════════════════════════════════════════════"
if ! command -v redis-server >/dev/null 2>&1 && ! command -v redis6-server >/dev/null 2>&1; then
  sudo dnf install -y redis6 || sudo dnf install -y redis
fi
# Resolve service + conf name. AL2023 ships 'redis6' (unit redis6.service,
# conf /etc/redis6/redis6.conf, owned by user redis6 so it needs sudo to stat).
# Older/other distros use plain 'redis'. Detect by which unit file exists.
if systemctl list-unit-files redis6.service >/dev/null 2>&1; then
  REDIS_SVC="redis6"; REDIS_CONF="/etc/redis6/redis6.conf"
else
  REDIS_SVC="redis";  REDIS_CONF="/etc/redis/redis.conf"
fi
# The conf dir/file is root/redis-owned; use sudo to test and create if missing.
sudo test -f "\$REDIS_CONF" || { sudo mkdir -p "\$(dirname "\$REDIS_CONF")"; echo "# created by configure-backend.sh" | sudo tee "\$REDIS_CONF" >/dev/null; }
echo "   service=\$REDIS_SVC  conf=\$REDIS_CONF"

# Apply caps to the conf so they survive restarts, bound to localhost only.
# Strategy: strip any existing directive we manage (active OR commented), then
# append our canonical values once. Idempotent — re-running yields the same file.
sudo sed -i -E '/^#? *maxmemory[ -]/d; /^#? *bind /d; /^#? *appendonly /d' "\$REDIS_CONF"
sudo tee -a "\$REDIS_CONF" >/dev/null <<CONF
# ---- Apex managed caps (configure-backend.sh) ----
maxmemory \$REDIS_MAXMEMORY
maxmemory-policy noeviction
appendonly no
bind 127.0.0.1 -::1
CONF

sudo systemctl enable "\$REDIS_SVC" >/dev/null 2>&1 || true
sudo systemctl restart "\$REDIS_SVC"
sleep 1
REDIS_CLI=\$(command -v redis6-cli || command -v redis-cli)
echo -n "   Redis ping: "; \$REDIS_CLI ping
echo -n "   maxmemory:  "; \$REDIS_CLI config get maxmemory | tail -1
echo -n "   policy:     "; \$REDIS_CLI config get maxmemory-policy | tail -1

echo "════════════════════════════════════════════════════════"
echo " 4/9  PM2 + log rotation"
echo "════════════════════════════════════════════════════════"
command -v pm2 >/dev/null 2>&1 || sudo npm install -g pm2
pm2 install pm2-logrotate 2>/dev/null || true
pm2 set pm2-logrotate:max_size "\$PM2_LOG_MAX_SIZE"
pm2 set pm2-logrotate:retain "\$PM2_LOG_RETAIN"
pm2 set pm2-logrotate:compress true
pm2 set pm2-logrotate:rotateInterval '0 0 * * *'
echo "   pm2 \$(pm2 -v), logrotate max=\$PM2_LOG_MAX_SIZE retain=\$PM2_LOG_RETAIN"
# Start PM2 on boot (generates + installs the systemd unit for ec2-user)
sudo env PATH=\$PATH:/usr/bin pm2 startup systemd -u ec2-user --hp /home/ec2-user >/dev/null 2>&1 || true

echo "════════════════════════════════════════════════════════"
echo " 5/9  Chromium libraries (puppeteer / playwright)"
echo "════════════════════════════════════════════════════════"
# System libs headless Chromium needs on AL2023. Puppeteer downloads its own
# Chromium binary at npm-install time; these are the shared libraries it links.
sudo dnf install -y -q \
  alsa-lib atk at-spi2-atk at-spi2-core cups-libs libdrm libXcomposite \
  libXcursor libXdamage libXext libXi libXrandr libXScrnSaver libXtst \
  pango gtk3 nss mesa-libgbm libxkbcommon 2>/dev/null || \
  echo "   ⚠️  Some Chromium libs may be missing — verify Kite auto-login after first deploy."

echo "════════════════════════════════════════════════════════"
echo " 6/9  Swap (\${SWAP_SIZE_MB}MB) — OOM safety net"
echo "════════════════════════════════════════════════════════"
if ! sudo swapon --show | grep -q '/swapfile'; then
  sudo dd if=/dev/zero of=/swapfile bs=1M count="\$SWAP_SIZE_MB" status=none
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null
  sudo swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  echo "   swap enabled"
else
  echo "   swap already present"
fi
free -h | grep -i swap

echo "════════════════════════════════════════════════════════"
echo " 7/9  journald disk cap"
echo "════════════════════════════════════════════════════════"
sudo sed -i "s/^#\\?SystemMaxUse=.*/SystemMaxUse=\$JOURNALD_MAX/" /etc/systemd/journald.conf
sudo grep -q "^SystemMaxUse=" /etc/systemd/journald.conf || echo "SystemMaxUse=\$JOURNALD_MAX" | sudo tee -a /etc/systemd/journald.conf >/dev/null
sudo systemctl restart systemd-journald || true
echo "   SystemMaxUse=\$JOURNALD_MAX"

echo "════════════════════════════════════════════════════════"
echo " 8/9  nginx reverse proxy (WebSocket-aware)"
echo "════════════════════════════════════════════════════════"
command -v nginx >/dev/null 2>&1 || sudo dnf install -y nginx
sudo mkdir -p /etc/nginx/conf.d
sudo tee /etc/nginx/conf.d/\${DOMAIN}.conf >/dev/null <<NGINX
# Map for WebSocket connection upgrade
map \\\$http_upgrade \\\$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name \${DOMAIN};

    # Allow large request bodies to match the app's own 1mb+ needs
    client_max_body_size 5m;

    # WebSocket live-price stream — must NOT buffer, long timeouts
    location /ws/live-prices {
        proxy_pass http://127.0.0.1:\${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection \\\$connection_upgrade;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }

    location / {
        proxy_pass http://127.0.0.1:\${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_read_timeout 120s;
    }
}
NGINX
sudo nginx -t
sudo systemctl enable nginx >/dev/null 2>&1 || true
sudo systemctl restart nginx
echo "   nginx up, proxying :80 -> 127.0.0.1:\${APP_PORT}"

echo "════════════════════════════════════════════════════════"
echo " 9/9  TLS via certbot (Let's Encrypt)"
echo "════════════════════════════════════════════════════════"
command -v certbot >/dev/null 2>&1 || sudo dnf install -y certbot python3-certbot-nginx
# Only request a cert if one isn't already present for this domain.
if [ ! -d "/etc/letsencrypt/live/\${DOMAIN}" ]; then
  echo "   Requesting certificate for \${DOMAIN} ..."
  if sudo certbot --nginx -d "\${DOMAIN}" --non-interactive --agree-tos -m "\${CERTBOT_EMAIL}" --redirect; then
    echo "   ✅ TLS installed + HTTP->HTTPS redirect enabled"
  else
    echo "   ⚠️  certbot failed. Most common cause: DNS for \${DOMAIN} not yet"
    echo "       pointing at this box, or security group not allowing 80/443."
    echo "       Fix DNS/SG, then re-run this script (it will retry only certbot)."
  fi
else
  echo "   Certificate already present for \${DOMAIN}"
fi
# certbot installs a systemd timer for auto-renewal on AL2023; verify it's on.
sudo systemctl enable certbot-renew.timer >/dev/null 2>&1 || \
  sudo systemctl enable certbot.timer >/dev/null 2>&1 || true

echo ""
echo "✅ Provisioning complete on \$(hostname)."
echo "   Node:  \$(node -v)"
echo "   Redis: capped at \$REDIS_MAXMEMORY / noeviction"
echo "   nginx + TLS: \${DOMAIN}"
echo ""
echo "   Next: from your Mac run 'bash deploy/backend-prod.sh' to deploy the app,"
echo "   after placing the production .env at \${REMOTE_DIR}/.env"
REMOTE

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ configure-backend.sh finished for $EC2_HOST"
echo "════════════════════════════════════════════════════════"
echo "Remaining manual steps (see deploy/README-DEPLOY.md):"
echo "  1. Ensure security group allows inbound 22, 80, 443"
echo "  2. Upload production .env to $REMOTE_DIR/.env"
echo "  3. Run: bash deploy/backend-prod.sh"
