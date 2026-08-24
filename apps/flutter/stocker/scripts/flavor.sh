#!/usr/bin/env bash
#
# Build/run a white-label flavour with the Gradle flavour and the Dart brand
# define kept in sync — passing only one of the two is the main footgun here
# (you'd get e.g. Volt's icon with Apex's colours, or vice versa).
#
# Usage:
#   scripts/flavor.sh <brand> <flutter-command> [extra flutter args...]
#
# Examples:
#   scripts/flavor.sh apex run
#   scripts/flavor.sh volt run
#   scripts/flavor.sh volt build apk --release
#   scripts/flavor.sh apex build appbundle --release
#
# Brands are discovered from flutter_launcher_icons-<brand>.yaml, so adding a new
# white-label brand needs no change to this script.

set -euo pipefail

cd "$(dirname "$0")/.."

available() {
  # shellcheck disable=SC2012
  ls flutter_launcher_icons-*.yaml 2>/dev/null \
    | sed 's/flutter_launcher_icons-//; s/\.yaml//' \
    | tr '\n' ' '
}

if [ $# -lt 2 ]; then
  echo "usage: scripts/flavor.sh <brand> <flutter-command> [extra args...]" >&2
  echo "brands: $(available)" >&2
  echo "e.g.:   scripts/flavor.sh volt run" >&2
  exit 64
fi

BRAND="$1"; shift

if [ ! -f "flutter_launcher_icons-${BRAND}.yaml" ]; then
  echo "error: unknown brand '${BRAND}'" >&2
  echo "brands: $(available)" >&2
  exit 64
fi

# Every flavour's applicationId needs a matching client in google-services.json,
# otherwise the build dies in :app:process<Flavour>GoogleServices with a cryptic
# message. Catch it here with something actionable instead.
#
# This will fire again if google-services.json is re-downloaded from the Firebase
# console without Volt registered — that wipes the placeholder client entry.
APP_ID=$(sed -n "/^ *${BRAND} {/,/^ *}/p" android/app/build.gradle \
         | sed -n 's/.*applicationId "\(.*\)".*/\1/p' | head -1)

if [ -n "${APP_ID}" ] && ! grep -q "\"${APP_ID}\"" android/app/google-services.json 2>/dev/null; then
  echo "──────────────────────────────────────────────────────────────────────" >&2
  echo " android/app/google-services.json has no client for:" >&2
  echo "   ${APP_ID}   (flavour: ${BRAND})" >&2
  echo "" >&2
  echo " The Android build will fail in :app:process${BRAND}...GoogleServices." >&2
  echo "" >&2
  echo " Fix: register the app in the Firebase project and re-download" >&2
  echo "      google-services.json — see FLAVORS.md -> 'Firebase'." >&2
  echo "──────────────────────────────────────────────────────────────────────" >&2
  exit 1
fi

echo "▶ brand=${BRAND}  →  flutter $* --flavor ${BRAND} --dart-define=BRAND=${BRAND}"
exec flutter "$@" --flavor "${BRAND}" --dart-define=BRAND="${BRAND}"
