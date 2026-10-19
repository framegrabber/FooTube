#!/usr/bin/env bash
# Build FooTube for the paired Apple TV, install it and launch it.
#   scripts/run-device.sh [launch args...]      e.g. scripts/run-device.sh -play aqz-KE-bpKQ
# Device: first paired Apple TV reported by devicectl, or set FOOTUBE_DEVICE=<name or identifier>.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BUNDLE="com.felixrothballer.FooTube"
devices="$(mktemp)"
trap 'rm -f "$devices"' EXIT
xcrun devicectl list devices --json-output "$devices" >/dev/null 2>&1
# "<identifier>\t<name>" of the chosen paired Apple TV.
read -r DEVICE NAME < <(jq -r --arg want "${FOOTUBE_DEVICE:-}" '.result.devices[]
  | select(.hardwareProperties.deviceType == "appleTV" and .connectionProperties.pairingState == "paired")
  | select($want == "" or .identifier == $want or .deviceProperties.name == $want)
  | [.identifier, .deviceProperties.name] | @tsv' "$devices" | head -1) || true
[[ -n "${DEVICE:-}" ]] || { echo "No paired Apple TV found (xcrun devicectl list devices)." >&2; exit 1; }
DEST="platform=tvOS,id=$(xcrun devicectl device info details --device "$DEVICE" --json-output "$devices" >/dev/null 2>&1; jq -r '.result.deviceProperties.udid // empty' "$devices")"
[[ "$DEST" != "platform=tvOS,id=" ]] || DEST="platform=tvOS,name=$NAME"

xcodegen generate --quiet
xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination "$DEST" -allowProvisioningUpdates build | xcbeautify --quiet

products="$(xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination "$DEST" -showBuildSettings 2>/dev/null |
  awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')"

xcrun devicectl device install app --device "$DEVICE" "$products/FooTube.app" >/dev/null
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" "$@"
