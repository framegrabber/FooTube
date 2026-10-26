# Sourced by run-sim.sh and run-device.sh: sets `sync_args` to `-syncURL <url> -syncToken <token>`
# when FOOTUBE_SYNC_URL and FOOTUBE_SYNC_TOKEN are set, else when the file
# ${FOOTUBE_SYNC_ENV:-~/.config/footube/sync.env} exists and sets them (shell syntax, same names).
# The app saves both (URL in UserDefaults, token in the Keychain); the token never enters the
# repository, the bundle or the build settings, and this script never prints it.
set +x # tracing would print the token in the launch command

sync_args=()
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
  sync_args=(-syncURL "$FOOTUBE_SYNC_URL" -syncToken "$FOOTUBE_SYNC_TOKEN")
  echo "Sync: configuring $FOOTUBE_SYNC_URL (token ${#FOOTUBE_SYNC_TOKEN} characters)"
elif [[ -n "${FOOTUBE_SYNC_URL:-}${FOOTUBE_SYNC_TOKEN:-}" ]]; then
  echo "Sync needs both FOOTUBE_SYNC_URL and FOOTUBE_SYNC_TOKEN." >&2
  exit 1
fi
