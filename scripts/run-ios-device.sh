#!/usr/bin/env bash
# Build FooTube for a paired iPhone or iPad, install it and launch it.
#   scripts/run-ios-device.sh [launch args...]      e.g. scripts/run-ios-device.sh -play aqz-KE-bpKQ
# Device: first paired iPhone or iPad reported by devicectl, or set FOOTUBE_DEVICE=<name or identifier>.
# The device needs Developer Mode on (Settings → Privacy & Security) and, after the first install, the
# developer profile trusted (Settings → General → VPN & Device Management).
# Sync: with FOOTUBE_SYNC_URL and FOOTUBE_SYNC_TOKEN set (or in $FOOTUBE_SYNC_ENV, default
# ~/.config/footube/sync.env) a configuration file goes into the app's container before launch; the
# app keeps URL and token and deletes the file (scripts/sync-env.sh). `-syncReset YES` turns sync off.
# On the device, Settings → Sync also takes a pasted URL and token.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/sync-env.sh

devices="$(mktemp)"
trap 'rm -f "$devices" "$sync_file"' EXIT
xcrun devicectl list devices --json-output "$devices" >/dev/null 2>&1
# "<identifier>\t<name>" of the chosen paired iPhone or iPad.
read -r DEVICE NAME < <(jq -r --arg want "${FOOTUBE_DEVICE:-}" '.result.devices[]
  | select((.hardwareProperties.deviceType == "iPhone" or .hardwareProperties.deviceType == "iPad")
      and .connectionProperties.pairingState == "paired")
  | select($want == "" or .identifier == $want or .deviceProperties.name == $want)
  | [.identifier, .deviceProperties.name] | @tsv' "$devices" | head -1) || true
[[ -n "${DEVICE:-}" ]] || { echo "No paired iPhone or iPad found (xcrun devicectl list devices)." >&2; exit 1; }
DEST="platform=iOS,id=$(xcrun devicectl device info details --device "$DEVICE" --json-output "$devices" >/dev/null 2>&1; jq -r '.result.deviceProperties.udid // empty' "$devices")"
[[ "$DEST" != "platform=iOS,id=" ]] || DEST="platform=iOS,name=$NAME"

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
if ! xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" "$@"; then
  cat >&2 <<'EOF'

FooTube is installed but iOS refused to launch it. After the first install (and after switching
Apple IDs), trust your developer profile on the device: Settings → General → VPN & Device Management
→ your Apple ID under "Developer App" → Trust. Then open FooTube from the home screen or run this
script again.
EOF
  if [[ -n "$sync_file" ]]; then
    cat >&2 <<EOF
The sync configuration file (with the token) is already in FooTube's container on the device
($sync_destination) and stays there until FooTube opens, reads and deletes it.
EOF
  fi
  exit 1
fi
