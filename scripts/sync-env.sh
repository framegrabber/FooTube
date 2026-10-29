# Sourced by run-sim.sh, run-device.sh and run-ios-device.sh. When FOOTUBE_SYNC_URL and
# FOOTUBE_SYNC_TOKEN are set, or the file ${FOOTUBE_SYNC_ENV:-~/.config/footube/sync.env} sets them,
# writes them to `sync_file`, a temporary JSON file `{"url", "token"}` readable only by you and
# deleted when the calling script exits. The script copies it into the installed app's data
# container as `Library/Caches/footube-sync.json`; the app reads it at launch, saves URL
# (UserDefaults) and token (Keychain) and deletes it. The token never goes into the repository, the
# bundle, the build settings or a launch command (the system logs launch arguments), and this script
# never prints it.
#
# The file is data, not shell code: only lines `FOOTUBE_SYNC_URL=<value>` and
# `FOOTUBE_SYNC_TOKEN=<value>` count (optionally after `export `, the value optionally in single or
# double quotes, nothing expanded); everything else is ignored. It must belong to you and must not be
# writable by group or others (`chmod 600`), else the script stops.
set +x # tracing would print the token

sync_file=""
sync_destination="Library/Caches/footube-sync.json"

# Sets FOOTUBE_SYNC_URL/FOOTUBE_SYNC_TOKEN from the file's assignment lines; exits if the file could
# have been written by someone else.
read_sync_env() {
  local file="$1" owner mode line value
  local assignment='^(export[[:space:]]+)?FOOTUBE_SYNC_(URL|TOKEN)=(.*)$'
  local double_quoted='^"(.*)"$' single_quoted="^'(.*)'\$"
  read -r owner mode < <(stat -L -f '%u %Lp' "$file")
  if [[ "$owner" != "$(id -u)" ]] || (((8#$mode & 8#022) != 0)); then
    echo "Not reading $file: it must belong to you and not be writable by group or others (chmod 600 \"$file\")." >&2
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ $assignment ]] || continue
    local name="FOOTUBE_SYNC_${BASH_REMATCH[2]}"
    value="${BASH_REMATCH[3]%$'\r'}"
    if [[ "$value" =~ $double_quoted || "$value" =~ $single_quoted ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    printf -v "$name" '%s' "$value"
  done <"$file"
}

if [[ -z "${FOOTUBE_SYNC_URL:-}" || -z "${FOOTUBE_SYNC_TOKEN:-}" ]]; then
  sync_env="${FOOTUBE_SYNC_ENV:-$HOME/.config/footube/sync.env}"
  if [[ -f "$sync_env" ]]; then
    read_sync_env "$sync_env"
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
