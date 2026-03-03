#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly DEFAULT_OUTPUT_DIR="dist/releases"
readonly DEFAULT_TARGET=""

OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
TARGET="${DEFAULT_TARGET}"

usage() {
  cat <<'EOF_USAGE' >&2
Usage: scripts/build-release-binaries.sh [options]

Options:
  --output-dir <dir>  Output directory for release artifacts (default: dist/releases)
  --target <triple>   Rust target triple (default: host target)
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
      --output-dir)
        [ "$#" -ge 2 ] || die "missing value for --output-dir"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --target)
        [ "$#" -ge 2 ] || die "missing value for --target"
        TARGET="$2"
        shift 2
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

write_checksums() {
  local output_file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum *.tar.gz > "${output_file}"
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 *.tar.gz > "${output_file}"
    return
  fi

  die "missing checksum command: sha256sum or shasum"
}

resolve_target() {
  if [ -n "${TARGET}" ]; then
    return
  fi

  TARGET="$(rustc -vV | sed -n 's/^host: //p')"
  [ -n "${TARGET}" ] || die "unable to detect host rust target"
}

cargo_build() {
  if [ -n "${TARGET}" ]; then
    cargo build --workspace --release --locked --target "${TARGET}"
  else
    cargo build --workspace --release --locked
  fi
}

binary_path() {
  local name="$1"
  if [ -n "${TARGET}" ]; then
    printf 'target/%s/release/%s' "${TARGET}" "${name}"
  else
    printf 'target/release/%s' "${name}"
  fi
}

main() {
  parse_args "$@"
  require_cmd cargo
  require_cmd rustc
  require_cmd tar

  resolve_target
  cargo_build

  local artifact_dir
  artifact_dir="${OUTPUT_DIR}/${TARGET}"
  mkdir -p "${artifact_dir}"

  local relay_bin hook_bin
  relay_bin="$(binary_path webhook-relay)"
  hook_bin="$(binary_path kafka-openclaw-hook)"

  [ -x "${relay_bin}" ] || die "missing binary: ${relay_bin}"
  [ -x "${hook_bin}" ] || die "missing binary: ${hook_bin}"

  cp "${relay_bin}" "${artifact_dir}/webhook-relay"
  cp "${hook_bin}" "${artifact_dir}/kafka-openclaw-hook"

  (
    cd "${artifact_dir}"
    tar -czf "webhook-relay-${TARGET}.tar.gz" "webhook-relay"
    tar -czf "kafka-openclaw-hook-${TARGET}.tar.gz" "kafka-openclaw-hook"
    rm -f "webhook-relay" "kafka-openclaw-hook"
    write_checksums "SHA256SUMS-${TARGET}.txt"
  )

  log "release artifacts created in ${artifact_dir}"
}

main "$@"
