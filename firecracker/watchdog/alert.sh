#!/usr/bin/env bash
set -u

readonly DEFAULT_ALERT_ENV_FILE="/etc/firecracker/alerts.env"
readonly DEFAULT_ALERT_STATE_DIR="/var/lib/firecracker-watchdog"
readonly DEFAULT_ALERT_STATE_FALLBACK_DIR="/tmp/firecracker-watchdog/state"
readonly DEFAULT_ALERT_LOG_FILE="/var/log/firecracker/alerts.log"
readonly DEFAULT_ALERT_LOG_FALLBACK_FILE="/tmp/firecracker-watchdog/alerts.log"
readonly DEFAULT_ALERT_COOLDOWN_SECONDS="300"

ALERT_ENV_FILE="${ALERT_ENV_FILE:-${DEFAULT_ALERT_ENV_FILE}}"
if [ -f "${ALERT_ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  . "${ALERT_ENV_FILE}"
fi

pick_state_dir() {
  local candidate_dir="$1"
  local fallback_dir="$2"

  mkdir -p "${candidate_dir}" >/dev/null 2>&1 && [ -w "${candidate_dir}" ] && {
    printf '%s\n' "${candidate_dir}"
    return
  }

  mkdir -p "${fallback_dir}" >/dev/null 2>&1 && [ -w "${fallback_dir}" ] && {
    printf '%s\n' "${fallback_dir}"
    return
  }

  printf '%s\n' "${fallback_dir}"
}

pick_log_file() {
  local candidate_file="$1"
  local fallback_file="$2"
  local candidate_dir="$(dirname "${candidate_file}")"
  local fallback_dir="$(dirname "${fallback_file}")"

  mkdir -p "${candidate_dir}" >/dev/null 2>&1 && touch "${candidate_file}" >/dev/null 2>&1 && {
    printf '%s\n' "${candidate_file}"
    return
  }

  mkdir -p "${fallback_dir}" >/dev/null 2>&1 && touch "${fallback_file}" >/dev/null 2>&1 && {
    printf '%s\n' "${fallback_file}"
    return
  }

  printf '%s\n' "${fallback_file}"
}

ALERT_STATE_DIR="$(pick_state_dir "${ALERT_STATE_DIR:-${DEFAULT_ALERT_STATE_DIR}}" "${DEFAULT_ALERT_STATE_FALLBACK_DIR}")"
ALERT_COOLDOWN_SECONDS="${ALERT_COOLDOWN_SECONDS:-${DEFAULT_ALERT_COOLDOWN_SECONDS}}"
ALERT_HOST_LABEL="${ALERT_HOST_LABEL:-$(hostname)}"
ALERT_LOG_FILE="$(pick_log_file "${ALERT_LOG_FILE:-${DEFAULT_ALERT_LOG_FILE}}" "${DEFAULT_ALERT_LOG_FALLBACK_FILE}")"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

event_file() {
  local event_key="$1"
  local safe_event_key=""

  safe_event_key="$(printf '%s' "${event_key}" | tr -cs 'A-Za-z0-9._-' '_')"
  printf '%s/%s.last' "${ALERT_STATE_DIR}" "${safe_event_key}"
}

throttled() {
  local event_key="$1"
  local now_seconds="0"
  local previous_seconds="0"
  local state_file=""

  if [ ! -d "${ALERT_STATE_DIR}" ] || [ ! -w "${ALERT_STATE_DIR}" ]; then
    return 1
  fi

  now_seconds="$(date +%s)"
  state_file="$(event_file "${event_key}")"

  if [ -f "${state_file}" ]; then
    previous_seconds="$(cat "${state_file}" 2>/dev/null || printf '0')"
    if [ $((now_seconds - previous_seconds)) -lt "${ALERT_COOLDOWN_SECONDS}" ]; then
      return 0
    fi
  fi

  printf '%s' "${now_seconds}" > "${state_file}" 2>/dev/null || return 1
  return 1
}

send_webhook_alert() {
  local payload_json="$1"

  if [ -z "${ALERT_WEBHOOK_URL:-}" ]; then
    return 0
  fi

  if [ -n "${ALERT_WEBHOOK_BEARER_TOKEN:-}" ]; then
    curl -sS -m 8 -X POST "${ALERT_WEBHOOK_URL}" \
      -H "Authorization: Bearer ${ALERT_WEBHOOK_BEARER_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${payload_json}" >/dev/null 2>&1 || true
  else
    curl -sS -m 8 -X POST "${ALERT_WEBHOOK_URL}" \
      -H "Content-Type: application/json" \
      -d "${payload_json}" >/dev/null 2>&1 || true
  fi
}

send_email_alert() {
  local subject_line="$1"
  local body_text="$2"

  if [ -z "${ALERT_EMAIL_TO:-}" ]; then
    return 0
  fi

  if command -v sendmail >/dev/null 2>&1; then
    {
      printf 'To: %s\n' "${ALERT_EMAIL_TO}"
      printf 'From: %s\n' "${ALERT_EMAIL_FROM:-firecracker-alert@localhost}"
      printf 'Subject: %s\n' "${subject_line}"
      printf 'Content-Type: text/plain; charset=UTF-8\n\n'
      printf '%s\n' "${body_text}"
    } | sendmail -t >/dev/null 2>&1 || true
    return 0
  fi

  if command -v mail >/dev/null 2>&1; then
    printf '%s\n' "${body_text}" | mail -s "${subject_line}" "${ALERT_EMAIL_TO}" >/dev/null 2>&1 || true
  fi
}

alert_emit() {
  local severity="$1"
  local event_key="$2"
  local message_text="$3"
  local timestamp=""
  local line=""
  local escaped_message=""
  local escaped_host=""
  local escaped_event=""
  local payload_json=""
  local email_subject=""

  if throttled "${event_key}"; then
    return 0
  fi

  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  line="[${timestamp}] ALERT[${severity}][${event_key}] ${message_text}"
  printf '%s\n' "${line}" >> "${ALERT_LOG_FILE}" 2>/dev/null || true
  logger -t firecracker-alert "${line}" >/dev/null 2>&1 || true

  escaped_message="$(json_escape "${message_text}")"
  escaped_host="$(json_escape "${ALERT_HOST_LABEL}")"
  escaped_event="$(json_escape "${event_key}")"
  payload_json="$(printf '{"timestamp":"%s","host":"%s","severity":"%s","event":"%s","message":"%s"}' \
    "${timestamp}" "${escaped_host}" "${severity}" "${escaped_event}" "${escaped_message}")"

  send_webhook_alert "${payload_json}"

  email_subject="[${ALERT_HOST_LABEL}] firecracker ${severity}: ${event_key}"
  send_email_alert "${email_subject}" "${line}"
}
