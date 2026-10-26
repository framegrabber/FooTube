#!/usr/bin/env bash
# Build FooTube for the paired Apple TV, install it and launch it.
#   scripts/run-device.sh [launch args...]      e.g. scripts/run-device.sh -play aqz-KE-bpKQ
# Device: first paired Apple TV reported by devicectl, or set FOOTUBE_DEVICE=<name or identifier>.
# Sync: with FOOTUBE_SYNC_URL and FOOTUBE_SYNC_TOKEN set (or in $FOOTUBE_SYNC_ENV, default
# ~/.config/footube/sync.env) a configuration file goes into the app's container before launch; the
# app keeps URL and token and deletes the file (scripts/sync-env.sh). `-syncReset YES` turns sync off.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/sync-env.sh

devices="$(mktemp)"
trap 'rm -f "$devices" "$sync_file"' EXIT
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
settings="$(xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination "$DEST" -showBuildSettings 2>/dev/null)"
setting() { awk -F' = ' -v key=" $1" '$1 ~ key"$" {print $2; exit}' <<<"$settings"; }
[[ -n "$(setting DEVELOPMENT_TEAM)" ]] || {
  echo "No signing team: copy Config/Signing.local.xcconfig.example to Config/Signing.local.xcconfig and set your team (see README)." >&2
  exit 1
}
BUNDLE="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
products="$(setting BUILT_PRODUCTS_DIR)"

xcodebuild -project FooTube.xcodeproj -scheme FooTube -destination "$DEST" -allowProvisioningUpdates build | xcbeautify --quiet

xcrun devicectl device install app --device "$DEVICE" "$products/FooTube.app" >/dev/null
if [[ -n "$sync_file" ]]; then
  xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "$sync_file" --destination "$sync_destination" --quiet
fi
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" "$@"
