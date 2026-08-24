#!/bin/bash
# Build Apex release APK
# Usage: pnpm build:flutter:apex
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "${ROOT_DIR}/apps/flutter"
scripts/flavor.sh apex build apk --release

echo ""
echo "✅ Apex APK: apps/flutter/build/app/outputs/flutter-apk/app-apex-release.apk"
