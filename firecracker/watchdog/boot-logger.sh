#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly DEFAULT_LOG_DIR="/var/log/firecracker/watchdog"
readonly DEFAULT_FALLBACK_LOG_DIR="/tmp/firecracker-watchdog"
readonly DEFAULT_WATCHDOG_ENV_FILE="/etc/firecracker/watchdog.env"

WATCHDOG_ENV_FILE="${FIRECRACKER_WATCHDOG_ENV_FILE:-${DEFAULT_WATCHDOG_ENV_FILE}}"
if [ -f "${WATCHDOG_ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  . "${WATCHDOG_ENV_FILE}"
fi

WATCHDOG_LOG_DIR="${FIRECRACKER_WATCHDOG_LOG_DIR:-${DEFAULT_LOG_DIR}}"
WATCHDOG_FALLBACK_LOG_DIR="${FIRECRACKER_WATCHDOG_FALLBACK_LOG_DIR:-${DEFAULT_FALLBACK_LOG_DIR}}"

ensure_writable_dir() {
  local directory_path="$1"

  mkdir -p "${directory_path}" >/dev/null 2>&1 || return 1
  touch "${directory_path}/.write-test" >/dev/null 2>&1 || return 1
  rm -f "${directory_path}/.write-test" >/dev/null 2>&1 || true
  return 0
}

resolve_log_dir() {
  if ensure_writable_dir "${WATCHDOG_LOG_DIR}"; then
    printf '%s\n' "${WATCHDOG_LOG_DIR}"
    return
  fi

  if ensure_writable_dir "${WATCHDOG_FALLBACK_LOG_DIR}"; then
    printf '%s\n' "${WATCHDOG_FALLBACK_LOG_DIR}"
    return
  fi

  return 1
}

append_section_header() {
  local file_path="$1"
  local title="$2"

  {
    printf '\n'
    printf -- '--- %s ---\n' "${title}"
  } >> "${file_path}"
}

append_dmesg_matches() {
  local file_path="$1"
  local pattern="$2"
  local max_lines="$3"

  if command -v dmesg >/dev/null 2>&1; then
    dmesg | grep -Ei "${pattern}" | head -n "${max_lines}" >> "${file_path}" 2>&1 || true
  else
    printf 'dmesg unavailable\n' >> "${file_path}"
  fi
}

calculate_gap_seconds() {
  local from_timestamp="$1"
  local to_timestamp="$2"
  local from_epoch=""
  local to_epoch=""

  from_epoch="$(date -d "${from_timestamp}" +%s 2>/dev/null || true)"
  to_epoch="$(date -d "${to_timestamp}" +%s 2>/dev/null || true)"

  if [ -z "${from_epoch}" ] || [ -z "${to_epoch}" ]; then
    return 1
  fi

  printf '%s\n' "$((to_epoch - from_epoch))"
}

main() {
  local log_dir=""
  local boot_log=""
  local state_file=""
  local timestamp=""
  local last_timestamp="unknown"
  local last_uptime_seconds="unknown"
  local gap_seconds=""

  log_dir="$(resolve_log_dir || true)"
  if [ -z "${log_dir}" ]; then
    printf 'error: unable to write watchdog boot logs\n' >&2
    exit 1
  fi

  boot_log="${log_dir}/boot.log"
  state_file="${FIRECRACKER_WATCHDOG_STATE_FILE:-${log_dir}/last_state.json}"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  {
    printf '\n'
    printf '========== BOOT EVENT: %s ==========\n' "${timestamp}"
  } >> "${boot_log}"

  if [ -f "${state_file}" ]; then
    if command -v jq >/dev/null 2>&1; then
      last_timestamp="$(jq -r '.timestamp // "unknown"' "${state_file}" 2>/dev/null || printf 'unknown')"
      last_uptime_seconds="$(jq -r '.uptime_seconds // "unknown"' "${state_file}" 2>/dev/null || printf 'unknown')"
    fi

    printf 'Last heartbeat: %s (uptime was %ss)\n' "${last_timestamp}" "${last_uptime_seconds}" >> "${boot_log}"

    if [ "${last_timestamp}" != "unknown" ]; then
      gap_seconds="$(calculate_gap_seconds "${last_timestamp}" "${timestamp}" || true)"
      if [ -n "${gap_seconds}" ]; then
        printf 'Gap since last heartbeat: %ss (~%sh %sm)\n' \
          "${gap_seconds}" "$((gap_seconds / 3600))" "$(((gap_seconds % 3600) / 60))" >> "${boot_log}"
      fi
    fi

    append_section_header "${boot_log}" "Previous state"
    cat "${state_file}" >> "${boot_log}" 2>/dev/null || printf 'unable to read state file\n' >> "${boot_log}"
  else
    printf 'No previous state file found; first boot or logs were rotated\n' >> "${boot_log}"
  fi

  append_section_header "${boot_log}" "Kernel boot reason"
  append_dmesg_matches "${boot_log}" 'boot|reset|restart|recovery' 20

  append_section_header "${boot_log}" "Filesystem recovery"
  append_dmesg_matches "${boot_log}" 'EXT4-fs|recovery|mount' 20

  printf '\n========== END BOOT LOG ==========\n' >> "${boot_log}"
  sync
}

main "$@"
