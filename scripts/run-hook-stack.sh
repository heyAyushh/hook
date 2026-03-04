#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

HOOK_BIN="${HOOK_BIN:-hook}"
PROFILE="${HOOK_PROFILE:-default}"
RUN_SERVE=1
RUN_RELAY=1
RUN_SMASH=1

usage() {
  cat <<'EOF_USAGE' >&2
Usage: scripts/run-hook-stack.sh [options]

Options:
  --hook-bin <path>   hook binary path/command (default: hook)
  --profile <name>    profile name passed to each hook command
  --no-serve          skip serve process
  --no-relay          skip relay process
  --no-smash          skip smash process
EOF_USAGE
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --hook-bin)
        [ "$#" -ge 2 ] || { echo "error: missing value for --hook-bin" >&2; exit 1; }
        HOOK_BIN="$2"
        shift 2
        ;;
      --profile)
        [ "$#" -ge 2 ] || { echo "error: missing value for --profile" >&2; exit 1; }
        PROFILE="$2"
        shift 2
        ;;
      --no-serve)
        RUN_SERVE=0
        shift
        ;;
      --no-relay)
        RUN_RELAY=0
        shift
        ;;
      --no-smash)
        RUN_SMASH=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        echo "error: unknown option: $1" >&2
        exit 1
        ;;
    esac
  done
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing command: $1" >&2
    exit 1
  }
}

start_process() {
  local name="$1"
  shift
  echo "starting ${name}: $*" >&2
  "$@" &
  PIDS+=("$!")
  NAMES+=("${name}")
}

cleanup() {
  local index
  for index in "${!PIDS[@]}"; do
    if kill -0 "${PIDS[$index]}" >/dev/null 2>&1; then
      echo "stopping ${NAMES[$index]} (pid=${PIDS[$index]})" >&2
      kill "${PIDS[$index]}" >/dev/null 2>&1 || true
    fi
  done
}

main() {
  parse_args "$@"
  require_cmd "$HOOK_BIN"

  if [ "$RUN_SERVE" -eq 0 ] && [ "$RUN_RELAY" -eq 0 ] && [ "$RUN_SMASH" -eq 0 ]; then
    echo "error: at least one role must be enabled" >&2
    exit 1
  fi

  trap cleanup EXIT INT TERM

  PIDS=()
  NAMES=()

  if [ "$RUN_SERVE" -eq 1 ]; then
    start_process serve "$HOOK_BIN" --profile "$PROFILE" serve
  fi
  if [ "$RUN_RELAY" -eq 1 ]; then
    start_process relay "$HOOK_BIN" --profile "$PROFILE" relay
  fi
  if [ "$RUN_SMASH" -eq 1 ]; then
    start_process smash "$HOOK_BIN" --profile "$PROFILE" smash
  fi

  local failed=0
  local index
  for index in "${!PIDS[@]}"; do
    if ! wait "${PIDS[$index]}"; then
      echo "process failed: ${NAMES[$index]}" >&2
      failed=1
    fi
  done

  exit "$failed"
}

main "$@"
