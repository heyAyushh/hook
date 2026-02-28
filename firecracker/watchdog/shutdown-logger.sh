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

append_command_output() {
  local file_path="$1"
  local command_title="$2"
  shift 2

  append_section_header "${file_path}" "${command_title}"
  "$@" >> "${file_path}" 2>&1 || printf '%s command failed\n' "${command_title}" >> "${file_path}"
}

main() {
  local log_dir=""
  local shutdown_log=""
  local timestamp=""
  local uptime_seconds="0"

  log_dir="$(resolve_log_dir || true)"
  if [ -z "${log_dir}" ]; then
    printf 'error: unable to write watchdog shutdown logs\n' >&2
    exit 1
  fi

  shutdown_log="${log_dir}/shutdown.log"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  uptime_seconds="$(awk '{print $1}' /proc/uptime 2>/dev/null || printf '0')"

  {
    printf '\n'
    printf '========== SHUTDOWN EVENT: %s ==========\n' "${timestamp}"
    printf 'Uptime was: %ss\n' "${uptime_seconds}"
  } >> "${shutdown_log}"

  if command -v last >/dev/null 2>&1; then
    append_command_output "${shutdown_log}" "Last commands (wtmp)" last -5
  fi

  if command -v systemctl >/dev/null 2>&1; then
    append_command_output "${shutdown_log}" "Systemd shutdown target" systemctl list-jobs
  fi

  if command -v journalctl >/dev/null 2>&1; then
    append_command_output "${shutdown_log}" "Recent journal" journalctl -n 50 --no-pager
  fi

  if command -v free >/dev/null 2>&1; then
    append_command_output "${shutdown_log}" "Memory state" free -h
  fi

  if command -v ps >/dev/null 2>&1; then
    append_section_header "${shutdown_log}" "Process list"
    ps aux --sort=-%mem | head -20 >> "${shutdown_log}" 2>&1 || true
  fi

  if command -v dmesg >/dev/null 2>&1; then
    append_section_header "${shutdown_log}" "dmesg tail"
    dmesg | tail -30 >> "${shutdown_log}" 2>&1 || true
  fi

  if command -v ss >/dev/null 2>&1; then
    append_section_header "${shutdown_log}" "Network connections"
    ss -tunp | head -30 >> "${shutdown_log}" 2>&1 || true
  fi

  printf '\n========== END SHUTDOWN LOG ==========\n' >> "${shutdown_log}"
  sync
  sync
}

main "$@"
