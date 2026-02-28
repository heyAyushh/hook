#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly DEFAULT_LOG_DIR="/var/log/firecracker/watchdog"
readonly DEFAULT_FALLBACK_LOG_DIR="/tmp/firecracker-watchdog"
readonly DEFAULT_WATCHDOG_TIMER_UNIT="firecracker-watchdog.timer"
readonly DEFAULT_WATCHDOG_SERVICE_UNIT="firecracker-watchdog.service"
readonly DEFAULT_WATCHDOG_ENV_FILE="/etc/firecracker/watchdog.env"

WATCHDOG_ENV_FILE="${FIRECRACKER_WATCHDOG_ENV_FILE:-${DEFAULT_WATCHDOG_ENV_FILE}}"
if [ -f "${WATCHDOG_ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  . "${WATCHDOG_ENV_FILE}"
fi

WATCHDOG_LOG_DIR="${FIRECRACKER_WATCHDOG_LOG_DIR:-${DEFAULT_LOG_DIR}}"
WATCHDOG_FALLBACK_LOG_DIR="${FIRECRACKER_WATCHDOG_FALLBACK_LOG_DIR:-${DEFAULT_FALLBACK_LOG_DIR}}"
WATCHDOG_TIMER_UNIT="${FIRECRACKER_WATCHDOG_TIMER_UNIT:-${DEFAULT_WATCHDOG_TIMER_UNIT}}"
WATCHDOG_SERVICE_UNIT="${FIRECRACKER_WATCHDOG_SERVICE_UNIT:-${DEFAULT_WATCHDOG_SERVICE_UNIT}}"

if [ ! -d "${WATCHDOG_LOG_DIR}" ] && [ -d "${WATCHDOG_FALLBACK_LOG_DIR}" ]; then
  WATCHDOG_LOG_DIR="${WATCHDOG_FALLBACK_LOG_DIR}"
fi

STATE_FILE="${WATCHDOG_LOG_DIR}/last_state.json"
HEARTBEAT_FILE="${WATCHDOG_LOG_DIR}/heartbeat.log"
BOOT_LOG_FILE="${WATCHDOG_LOG_DIR}/boot.log"
SHUTDOWN_LOG_FILE="${WATCHDOG_LOG_DIR}/shutdown.log"

echo "=== Firecracker Watchdog Status ==="
if command -v systemctl >/dev/null 2>&1; then
  systemctl status --no-pager --lines=0 "${WATCHDOG_TIMER_UNIT}" "${WATCHDOG_SERVICE_UNIT}" 2>/dev/null || true
else
  echo "systemctl unavailable"
fi

echo
if [ -f "${STATE_FILE}" ] && command -v jq >/dev/null 2>&1; then
  echo "Current State:"
  jq -r '
    "  Last heartbeat: \(.timestamp)"
    + "\n  Uptime: \(.uptime_seconds | tonumber | floor)s"
    + "\n  Memory: \(.memory.available_kb / 1024 | floor)MB / \(.memory.total_kb / 1024 | floor)MB available"
    + "\n  Load: \(.load)"
    + "\n  Relay: \(.vms.relay.ping):\(.vms.relay.port_8080):\(.vms.relay.service)"
    + (if (.vms.kafka_brokers? | type) == "array" and (.vms.kafka_brokers | length) > 0
       then "\n  Kafka Brokers: " + ([.vms.kafka_brokers[] | "\(.id)=\(.ping):\(.port_9092):\(.service)"] | join(", "))
       else ""
       end)
    + "\n  External: \(.external_connectivity)"
  ' "${STATE_FILE}"
else
  echo "No state file: ${STATE_FILE}"
fi

echo
if [ -f "${HEARTBEAT_FILE}" ]; then
  echo "Recent Heartbeats:"
  tail -10 "${HEARTBEAT_FILE}"
fi

echo
if [ -f "${BOOT_LOG_FILE}" ]; then
  echo "Recent Boot Events:"
  grep -E "BOOT EVENT|Gap since|Last heartbeat" "${BOOT_LOG_FILE}" | tail -10 || true
fi

echo
if [ -f "${SHUTDOWN_LOG_FILE}" ]; then
  echo "Recent Shutdown Events:"
  grep "SHUTDOWN EVENT" "${SHUTDOWN_LOG_FILE}" | tail -5 || true
fi
