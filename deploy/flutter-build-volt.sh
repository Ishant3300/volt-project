#!/bin/bash
# Build Volt release APK and publish it for the in-app force-update check
# (see apps/flutter/lib/services/update_check_service.dart).
# Usage: pnpm build:flutter:volt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# New production server (c6i.large + 50GB gp3, ap-south-1) — see
# deploy/README-DEPLOY.md. The old 13.204.61.199 box was decommissioned
# after migration; this script silently published nowhere useful for a
# while after that until someone noticed, since scp/ssh to a dead host just
# times out rather than erroring obviously.
EC2_HOST="13.207.113.128"
EC2_USER="ec2-user"
# Per-developer SSH key path — override with APEX_SSH_KEY if yours differs
# from the default used on this machine.
SSH_KEY="${APEX_SSH_KEY:-$HOME/.ssh/apex_node_key}"
# Served directly by nginx's own `location /downloads/ { alias
# /var/www/downloads/; }` — NOT proxied to the Node process, so this must
# stay in sync with the actual nginx.conf on the server, not wherever the
# backend app itself lives.
REMOTE_DOWNLOADS_DIR="/var/www/downloads"

cd "${ROOT_DIR}/apps/flutter"
scripts/flavor.sh volt build apk --release

APK_PATH="build/app/outputs/flutter-apk/app-volt-release.apk"
echo ""
echo "✅ Volt APK: apps/flutter/${APK_PATH}"

# pubspec.yaml's build number IS the Android versionCode every build uses —
# reused here rather than re-deriving it, so the published version.json can
# never disagree with what the APK itself actually reports.
BUILD_NUMBER=$(grep -m1 '^version:' pubspec.yaml | sed -E 's/^version: [0-9.]+\+([0-9]+)/\1/')
if [ -z "${BUILD_NUMBER}" ]; then
  echo "❌ Could not parse build number from pubspec.yaml's version: line" >&2
  exit 1
fi

echo "📦 Publishing build ${BUILD_NUMBER} to ${EC2_HOST}..."
scp -i "$SSH_KEY" "${APK_PATH}" "${EC2_USER}@${EC2_HOST}:${REMOTE_DOWNLOADS_DIR}/app-volt-release.apk"
ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" \
  "echo '{\"build\": ${BUILD_NUMBER}, \"apk_url\": \"https://apexlive-api.mynpe.in/downloads/app-volt-release.apk\"}' > ${REMOTE_DOWNLOADS_DIR}/volt-version.json"

echo "✅ Published — every installed Volt build below ${BUILD_NUMBER} will now be prompted to update."
