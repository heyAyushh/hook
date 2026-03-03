#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DRY_RUN=0
ALLOW_DIRTY=0
SKIP_RELAY_CORE=0
SKIP_WEBHOOK_RELAY=0
SKIP_KAFKA_OPENCLAW_HOOK=0

usage() {
  cat <<'EOF_USAGE' >&2
Usage: scripts/publish-crates.sh [options]

Options:
  --dry-run                     Run cargo publish --dry-run only
  --allow-dirty                Allow publishing from a dirty worktree
  --skip-relay-core             Skip publishing relay-core
  --skip-webhook-relay          Skip publishing webhook-relay
  --skip-kafka-openclaw-hook    Skip publishing kafka-openclaw-hook
EOF_USAGE
}

log() {
  printf '%s\n' "$*" >&2
}

die() {
  log "error: $*"
  exit 1
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --allow-dirty)
        ALLOW_DIRTY=1
        shift
        ;;
      --skip-relay-core)
        SKIP_RELAY_CORE=1
        shift
        ;;
      --skip-webhook-relay)
        SKIP_WEBHOOK_RELAY=1
        shift
        ;;
      --skip-kafka-openclaw-hook)
        SKIP_KAFKA_OPENCLAW_HOOK=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        die "unknown option: $1"
        ;;
    esac
  done
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "missing command: ${cmd}"
}

publish_one() {
  local package="$1"
  local flags=(--locked)

  if [ "${ALLOW_DIRTY}" -eq 1 ]; then
    flags+=(--allow-dirty)
  fi

  if [ "${DRY_RUN}" -eq 1 ] && [ "${package}" != "relay-core" ]; then
    # Downstream crates depend on relay-core being available on crates.io.
    # Before relay-core is published for a new version, do a compile check instead.
    log "dry-run readiness check (compile only): ${package}"
    cargo check -p "${package}"
    return
  fi

  if [ "${DRY_RUN}" -eq 1 ]; then
    flags+=(--dry-run)
  fi

  log "publishing package: ${package}"
  cargo publish -p "${package}" "${flags[@]}"
}

main() {
  parse_args "$@"
  require_cmd cargo

  if [ "${DRY_RUN}" -ne 1 ] && [ -z "${CARGO_REGISTRY_TOKEN:-}" ]; then
    die "CARGO_REGISTRY_TOKEN is required for non-dry-run publish"
  fi

  if [ "${SKIP_RELAY_CORE}" -ne 1 ]; then
    publish_one relay-core
    if [ "${DRY_RUN}" -ne 1 ]; then
      sleep 20
    fi
  fi

  if [ "${SKIP_WEBHOOK_RELAY}" -ne 1 ]; then
    publish_one webhook-relay
    if [ "${DRY_RUN}" -ne 1 ]; then
      sleep 20
    fi
  fi

  if [ "${SKIP_KAFKA_OPENCLAW_HOOK}" -ne 1 ]; then
    publish_one kafka-openclaw-hook
  fi

  log "publish flow completed"
}

main "$@"
