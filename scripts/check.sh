#!/usr/bin/env bash
# Runs the checks defined in CONSTRAINTS.md (the canonical source; this script mirrors it).
#   scripts/check.sh fast   floor, format, secrets            (after edits, a few seconds)
#   scripts/check.sh task   fast + core build/tests, app build, dependencies   (task end, ~90 s)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

mode="${1:-fast}"
failed=()

run() {
  local name="$1"; shift
  echo "==> $name"
  if ! "$@"; then failed+=("$name"); fi
}

skip() { echo "==> $1: SKIP ($2)"; }

osv() {
  local out status
  out="$(osv-scanner scan source -r --format table . 2>&1)"; status=$?
  # 128 = no lockfiles yet (no dependencies resolved): nothing to scan.
  if [[ $status -eq 128 ]] && grep -q "No package sources found" <<<"$out"; then
    echo "no Package.resolved yet"; return 0
  fi
  echo "$out"
  [[ $status -eq 0 ]] && return 0
  # Non-zero means findings; block only on high/critical.
  ! grep -Eiq '\b(HIGH|CRITICAL)\b' <<<"$out"
}

app_build() {
  xcodegen generate --quiet &&
    xcodebuild -project FooTube.xcodeproj -scheme FooTube \
      -destination 'platform=tvOS Simulator,name=Apple TV' build | xcbeautify --quiet
}

run "floor"   node scripts/floor-guard.mjs
run "format"  swiftformat --lint --quiet .
run "secrets" gitleaks dir --redact --no-banner --log-level warn .

if [[ "$mode" == "task" ]]; then
  if [[ -f Packages/FooTubeCore/Package.swift ]]; then
    run "core build" swift build --package-path Packages/FooTubeCore
    run "core tests" swift test --package-path Packages/FooTubeCore
  else
    skip "core build/tests" "Packages/FooTubeCore not created yet"
  fi
  if [[ -f project.yml ]]; then
    run "app build" app_build
  else
    skip "app build" "project.yml not created yet"
  fi
  run "dependencies" osv
elif [[ "$mode" != "fast" ]]; then
  echo "usage: scripts/check.sh [fast|task]" >&2; exit 2
fi

if (( ${#failed[@]} )); then
  echo "FAILED: ${failed[*]}" >&2; exit 1
fi
echo "All checks passed ($mode)."
