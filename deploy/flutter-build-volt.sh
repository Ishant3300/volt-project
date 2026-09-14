#!/bin/bash
# Build Volt release APK and publish it for the in-app force-update check
# (see apps/flutter/lib/services/update_check_service.dart).
# Usage: pnpm build:flutter:volt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

EC2_HOST="13.204.61.199"
EC2_USER="ec2-user"
SSH_KEY="/Users/devarshukani/Work/Keys/apex/my-ec2-key"
REMOTE_DOWNLOADS_DIR="/home/ec2-user/stocker-backend-node/public/downloads"

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
ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" "mkdir -p ${REMOTE_DOWNLOADS_DIR}"
scp -i "$SSH_KEY" "${APK_PATH}" "${EC2_USER}@${EC2_HOST}:${REMOTE_DOWNLOADS_DIR}/volt-latest.apk"
ssh -i "$SSH_KEY" "${EC2_USER}@${EC2_HOST}" \
  "echo '{\"build\": ${BUILD_NUMBER}, \"apk_url\": \"https://apexlive-api.mynpe.in/downloads/volt-latest.apk\"}' > ${REMOTE_DOWNLOADS_DIR}/volt-version.json"

echo "✅ Published — every installed Volt build below ${BUILD_NUMBER} will now be prompted to update."
