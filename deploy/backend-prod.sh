#!/bin/bash
# Deploy backend to EC2 production server
# Usage: bash deploy/backend-prod.sh   (or: pnpm deploy:backend:prod)
#
# Prereq (run ONCE on a fresh box): bash deploy/configure-backend.sh
# That installs Node/Redis/PM2/nginx/TLS and all the log/memory caps.
# This script only ships code + restarts the app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="${ROOT_DIR}/apps/backend"

# ── New production server (c6i.large + 50GB gp3, ap-south-1) ──
EC2_HOST="13.207.113.128"
EC2_USER="ec2-user"
SSH_KEY="/Users/devarshukani/Work/Keys/apex/apex-backend-prod.pem"
REMOTE_DIR="/home/ec2-user/stocker-backend-node"
PM2_APP="stocker-backend-node"

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"

if [ ! -f "$SSH_KEY" ]; then
  echo "❌ SSH key not found at $SSH_KEY"
  exit 1
fi
chmod 400 "$SSH_KEY" 2>/dev/null || true

echo "🚀 Deploying backend to production ($EC2_HOST)..."

# Guard: refuse to deploy if the production .env is missing on the server.
# rsync excludes .env (below), so a first deploy without it would boot the app
# with no MONGO_URI/secrets and crash-loop. Fail loudly instead.
echo "🔎 Checking prerequisites on server..."
ssh -i "$SSH_KEY" $SSH_OPTS "${EC2_USER}@${EC2_HOST}" "bash -s" <<EOF
  set -e
  mkdir -p "${REMOTE_DIR}"
  if [ ! -f "${REMOTE_DIR}/.env" ]; then
    echo "❌ Missing ${REMOTE_DIR}/.env on server."
    echo "   Upload it first, e.g.:"
    echo "     scp -i \$SSH_KEY apps/backend/.env.production ${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/.env"
    exit 1
  fi
  command -v node >/dev/null || { echo "❌ node not found — run configure-backend.sh first."; exit 1; }
  command -v pm2  >/dev/null || { echo "❌ pm2 not found — run configure-backend.sh first."; exit 1; }
EOF

echo "🧹 Cleaning up remote server..."
ssh -i "$SSH_KEY" $SSH_OPTS "${EC2_USER}@${EC2_HOST}" <<'EOF'
  npm cache clean --force || true
  sudo journalctl --vacuum-size=100M || true
  sudo rm -rf /tmp/rsync* || true
EOF

echo "📦 Uploading files..."
rsync -avz --inplace --delete \
  -e "ssh -i $SSH_KEY $SSH_OPTS" \
  --exclude 'node_modules' \
  --exclude '.env' \
  --exclude 'dump.rdb' \
  --exclude 'scripts/downloads' \
  --exclude '.git' \
  --exclude 'test' \
  --exclude 'tests' \
  "${BACKEND_DIR}/" "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/"

echo "🔄 Installing dependencies and restarting..."
ssh -i "$SSH_KEY" $SSH_OPTS "${EC2_USER}@${EC2_HOST}" "bash -s" <<EOF
  set -e
  cd "${REMOTE_DIR}"
  npm install --production

  # Re-assert log rotation every deploy (harmless if already set) so a fresh
  # pm2 daemon after a reboot never runs uncapped.
  pm2 install pm2-logrotate 2>/dev/null || true
  pm2 set pm2-logrotate:max_size 100M
  pm2 set pm2-logrotate:retain 7
  pm2 set pm2-logrotate:compress true

  pm2 restart "${PM2_APP}" --update-env || pm2 start src/index.js --name "${PM2_APP}" --time

  # Persist the process list so PM2 resurrects the app on reboot.
  pm2 save

  echo "✅ Deployed and restarted"
  pm2 status "${PM2_APP}"
EOF

echo "✅ Deploy complete! → https://apexlive-api.mynpe.in"
