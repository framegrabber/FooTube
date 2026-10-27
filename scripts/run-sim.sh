#!/usr/bin/env bash
# Build FooTube, install it on a Simulator and launch it.
#   scripts/run-sim.sh [--ios | --ipad] [extra launch args...]
# Default: the "Apple TV" Simulator. --ios: "iPhone 17"; --ipad: "iPad Pro 11-inch (M5)";
# FOOTUBE_SIM=<name> picks another Simulator of that platform.
# Sync: with FOOTUBE_SYNC_URL and FOOTUBE_SYNC_TOKEN set (or in $FOOTUBE_SYNC_ENV, default
# ~/.config/footube/sync.env) a configuration file goes into the app's container before launch; the
# app keeps URL and token and deletes the file (scripts/sync-env.sh). `-syncReset YES` turns sync off.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

case "${1:-}" in
  --ios) SIM="${FOOTUBE_SIM:-iPhone 17}"; PLATFORM="iOS Simulator"; shift ;;
  --ipad) SIM="${FOOTUBE_SIM:-iPad Pro 11-inch (M5)}"; PLATFORM="iOS Simulator"; shift ;;
  *) SIM="${FOOTUBE_SIM:-Apple TV}"; PLATFORM="tvOS Simulator" ;;
esac
DEST="platform=$PLATFORM,name=$SIM"

source scripts/sync-env.sh

xcodegen generate --quiet
xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination "$DEST" build | xcbeautify --quiet

settings="$(xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination "$DEST" -showBuildSettings 2>/dev/null)"
setting() { awk -F' = ' -v key=" $1" '$1 ~ key"$" {print $2; exit}' <<<"$settings"; }
BUNDLE="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
products="$(setting BUILT_PRODUCTS_DIR)"

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" >/dev/null
# Show the window (simctl boots headless); FOOTUBE_HEADLESS=1 skips this for scripted runs.
[[ -n "${FOOTUBE_HEADLESS:-}" ]] || open -a Simulator
xcrun simctl install "$SIM" "$products/FooTube.app"
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
if [[ -n "$sync_file" ]]; then
  container="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)"
  mkdir -p "$(dirname "$container/$sync_destination")"
  cp "$sync_file" "$container/$sync_destination"
fi
xcrun simctl launch "$SIM" "$BUNDLE" "$@"
