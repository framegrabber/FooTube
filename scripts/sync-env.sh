# Sourced by run-sim.sh and run-device.sh. When FOOTUBE_SYNC_URL and FOOTUBE_SYNC_TOKEN are set, or
# the file ${FOOTUBE_SYNC_ENV:-~/.config/footube/sync.env} exists and sets them (shell syntax, same
# names), writes them to `sync_file`, a temporary JSON file `{"url", "token"}` readable only by you
# and deleted when the calling script exits. The script copies it into the installed app's data
# container as `Library/Caches/footube-sync.json`; the app reads it at launch, saves URL
# (UserDefaults) and token (Keychain) and deletes it. The token never goes into the repository, the
# bundle, the build settings or a launch command (the system logs launch arguments), and this script
# never prints it.
set +x # tracing would print the token

sync_file=""
sync_destination="Library/Caches/footube-sync.json"
if [[ -z "${FOOTUBE_SYNC_URL:-}" || -z "${FOOTUBE_SYNC_TOKEN:-}" ]]; then
  sync_env="${FOOTUBE_SYNC_ENV:-$HOME/.config/footube/sync.env}"
  if [[ -f "$sync_env" ]]; then
    # shellcheck source=/dev/null
    source "$sync_env"
  elif [[ -n "${FOOTUBE_SYNC_ENV:-}" ]]; then
    echo "FOOTUBE_SYNC_ENV=$FOOTUBE_SYNC_ENV does not exist." >&2
    exit 1
  fi
fi
if [[ -n "${FOOTUBE_SYNC_URL:-}" && -n "${FOOTUBE_SYNC_TOKEN:-}" ]]; then
  sync_file="$(umask 077 && mktemp -t footube-sync)"
  trap 'rm -f "$sync_file"' EXIT
  # Values through the environment, not jq's arguments (visible in `ps`).
  FOOTUBE_SYNC_URL="$FOOTUBE_SYNC_URL" FOOTUBE_SYNC_TOKEN="$FOOTUBE_SYNC_TOKEN" \
    jq -n '{url: env.FOOTUBE_SYNC_URL, token: env.FOOTUBE_SYNC_TOKEN}' >"$sync_file"
  echo "Sync: configuring $FOOTUBE_SYNC_URL (token ${#FOOTUBE_SYNC_TOKEN} characters)"
elif [[ -n "${FOOTUBE_SYNC_URL:-}${FOOTUBE_SYNC_TOKEN:-}" ]]; then
  echo "Sync needs both FOOTUBE_SYNC_URL and FOOTUBE_SYNC_TOKEN." >&2
  exit 1
fi
