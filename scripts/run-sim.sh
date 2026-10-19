#!/usr/bin/env bash
# Build FooTube, install it on the "Apple TV" Simulator and launch it.
#   scripts/run-sim.sh [extra launch args...]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SIM="Apple TV"
DEST="platform=tvOS Simulator,name=$SIM"

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
xcrun simctl launch "$SIM" "$BUNDLE" "$@"
