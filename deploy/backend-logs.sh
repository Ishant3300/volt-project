#!/bin/bash
# SSH to production and tail PM2 logs
# Usage: pnpm deploy:backend:logs
set -e

EC2_HOST="13.204.61.199"
EC2_USER="ec2-user"
SSH_KEY="/Users/devarshukani/Work/Keys/apex/my-ec2-key"
PM2_APP="stocker-backend-node"

echo "📡 Connecting to $EC2_HOST — streaming $PM2_APP logs (Ctrl+C to stop)..."
ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" "pm2 logs $PM2_APP --lines 50"
