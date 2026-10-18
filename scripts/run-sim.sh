#!/usr/bin/env bash
# Build FooTube, install it on the "Apple TV" Simulator and launch it.
#   scripts/run-sim.sh [extra launch args...]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SIM="Apple TV"
BUNDLE="com.felixrothballer.FooTube"
DEST="platform=tvOS Simulator,name=$SIM"

xcodegen generate --quiet
xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination "$DEST" build | xcbeautify --quiet

products="$(xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination "$DEST" -showBuildSettings 2>/dev/null |
  awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')"

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" >/dev/null
xcrun simctl install "$SIM" "$products/FooTube.app"
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$SIM" "$BUNDLE" "$@"
