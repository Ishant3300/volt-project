#!/bin/bash
# Build Volt release APK
# Usage: pnpm build:flutter:volt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "${ROOT_DIR}/apps/flutter"
scripts/flavor.sh volt build apk --release

echo ""
echo "✅ Volt APK: apps/flutter/build/app/outputs/flutter-apk/app-volt-release.apk"
