#!/usr/bin/env bash
# Run from a separate host to detect ingress outages.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_ENV_FILE="/etc/firecracker/external-blackbox.env"
readonly DEFAULT_ALERT_HELPER_SCRIPT="${SCRIPT_DIR}/alert.sh"
readonly DEFAULT_LOG_FILE="/var/log/firecracker/external-blackbox.log"
readonly DEFAULT_FALLBACK_LOG_FILE="/tmp/firecracker-watchdog/external-blackbox.log"
readonly DEFAULT_EXPECT_WEBHOOK_CODE="401"
readonly DEFAULT_EXPECT_ROOT_CODE="200"
readonly DEFAULT_TIMEOUT_SECONDS="8"

BLACKBOX_ENV_FILE="${BLACKBOX_ENV_FILE:-${DEFAULT_ENV_FILE}}"
if [ -f "${BLACKBOX_ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  . "${BLACKBOX_ENV_FILE}"
fi

ALERT_HELPER_SCRIPT="${FIRECRACKER_WATCHDOG_ALERT_HELPER:-${DEFAULT_ALERT_HELPER_SCRIPT}}"
if [ -f "${ALERT_HELPER_SCRIPT}" ]; then
  # shellcheck disable=SC1090
  . "${ALERT_HELPER_SCRIPT}"
fi

if ! declare -F alert_emit >/dev/null 2>&1; then
  alert_emit() {
    :
  }
fi

BLACKBOX_BASE_URL="${BLACKBOX_BASE_URL:-}"
BLACKBOX_EXPECT_WEBHOOK_CODE="${BLACKBOX_EXPECT_WEBHOOK_CODE:-${DEFAULT_EXPECT_WEBHOOK_CODE}}"
BLACKBOX_EXPECT_ROOT_CODE="${BLACKBOX_EXPECT_ROOT_CODE:-${DEFAULT_EXPECT_ROOT_CODE}}"
BLACKBOX_TIMEOUT_SECONDS="${BLACKBOX_TIMEOUT_SECONDS:-${DEFAULT_TIMEOUT_SECONDS}}"
BLACKBOX_LOG_FILE="${BLACKBOX_LOG_FILE:-${DEFAULT_LOG_FILE}}"

resolve_log_file() {
  local candidate_file="$1"
  local fallback_file="$2"

  mkdir -p "$(dirname "${candidate_file}")" >/dev/null 2>&1 && touch "${candidate_file}" >/dev/null 2>&1 && {
    printf '%s\n' "${candidate_file}"
    return
  }

  mkdir -p "$(dirname "${fallback_file}")" >/dev/null 2>&1
  touch "${fallback_file}" >/dev/null 2>&1 || true
  printf '%s\n' "${fallback_file}"
}

BLACKBOX_LOG_FILE="$(resolve_log_file "${BLACKBOX_LOG_FILE}" "${DEFAULT_FALLBACK_LOG_FILE}")"

log() {
  local now_text=""

  now_text="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] %s\n' "${now_text}" "$1" | tee -a "${BLACKBOX_LOG_FILE}" >&2
}

normalize_base_url() {
  local url="$1"
  printf '%s\n' "${url%/}"
}

http_code() {
  local method="$1"
  local url="$2"
  local body="${3:-}"

  if [ -n "${body}" ]; then
    curl -sS -m "${BLACKBOX_TIMEOUT_SECONDS}" -o /dev/null -w '%{http_code}' -X "${method}" "${url}" -d "${body}" 2>/dev/null || printf '000'
  else
    curl -sS -m "${BLACKBOX_TIMEOUT_SECONDS}" -o /dev/null -w '%{http_code}' -X "${method}" "${url}" 2>/dev/null || printf '000'
  fi
}

main() {
  local failed=0
  local normalized_base_url=""
  local webhook_code=""
  local root_code=""

  if [ -z "${BLACKBOX_BASE_URL}" ]; then
    log "FAIL: BLACKBOX_BASE_URL is required"
    exit 2
  fi

  normalized_base_url="$(normalize_base_url "${BLACKBOX_BASE_URL}")"
  webhook_code="$(http_code POST "${normalized_base_url}/webhook/github" '{}')"
  root_code="$(http_code GET "${normalized_base_url}/")"

  if [ "${webhook_code}" != "${BLACKBOX_EXPECT_WEBHOOK_CODE}" ]; then
    failed=1
    log "FAIL: /webhook/github returned ${webhook_code} (expected ${BLACKBOX_EXPECT_WEBHOOK_CODE})"
  fi

  if [ "${root_code}" != "${BLACKBOX_EXPECT_ROOT_CODE}" ]; then
    failed=1
    log "FAIL: / returned ${root_code} (expected ${BLACKBOX_EXPECT_ROOT_CODE})"
  fi

  if [ "${failed}" -eq 0 ]; then
    log "OK: external black-box checks passed (${normalized_base_url})"
    exit 0
  fi

  alert_emit critical "external_blackbox_failed" \
    "External checks failed for ${normalized_base_url} (webhook=${webhook_code} root=${root_code})."
  exit 1
}

main "$@"
