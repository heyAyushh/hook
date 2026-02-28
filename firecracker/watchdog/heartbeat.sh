#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_LOG_DIR="/var/log/firecracker/watchdog"
readonly DEFAULT_FALLBACK_LOG_DIR="/tmp/firecracker-watchdog"
readonly DEFAULT_BROKER_INVENTORY_SCRIPT="${SCRIPT_DIR}/../runtime/broker_inventory.sh"
readonly DEFAULT_BROKER_ROW=$'kafka\t1\t172.30.0.10\ttap-kafka\t/tmp/kafka-fc.sock\t9092\t\t'
readonly DEFAULT_RELAY_VM_IP="172.30.0.20"
readonly DEFAULT_RELAY_VM_PORT="8080"
readonly DEFAULT_RELAY_SERVICE_NAME="firecracker@relay.service"
readonly DEFAULT_RELAY_SOCKET_PATH="/tmp/relay-fc.sock"
readonly DEFAULT_RELAY_HEALTH_URL=""
readonly DEFAULT_SERVICE_LIST="firecracker@relay.service"
readonly DEFAULT_BROKER_SERVICE_TEMPLATE="firecracker@%s.service"
readonly DEFAULT_BROKER_SOCKET_TEMPLATE="/tmp/%s-fc.sock"
readonly DEFAULT_BROKER_PORT="9092"
readonly DEFAULT_WATCHDOG_ENV_FILE="/etc/firecracker/watchdog.env"

WATCHDOG_ENV_FILE="${FIRECRACKER_WATCHDOG_ENV_FILE:-${DEFAULT_WATCHDOG_ENV_FILE}}"
if [ -f "${WATCHDOG_ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  . "${WATCHDOG_ENV_FILE}"
fi

WATCHDOG_LOG_DIR="${FIRECRACKER_WATCHDOG_LOG_DIR:-${DEFAULT_LOG_DIR}}"
WATCHDOG_FALLBACK_LOG_DIR="${FIRECRACKER_WATCHDOG_FALLBACK_LOG_DIR:-${DEFAULT_FALLBACK_LOG_DIR}}"
BROKER_INVENTORY_SCRIPT="${FIRECRACKER_BROKER_INVENTORY_SCRIPT:-${DEFAULT_BROKER_INVENTORY_SCRIPT}}"
RELAY_VM_IP="${FIRECRACKER_WATCHDOG_RELAY_VM_IP:-${DEFAULT_RELAY_VM_IP}}"
RELAY_VM_PORT="${FIRECRACKER_WATCHDOG_RELAY_VM_PORT:-${DEFAULT_RELAY_VM_PORT}}"
RELAY_SERVICE_NAME="${FIRECRACKER_WATCHDOG_RELAY_SERVICE:-${DEFAULT_RELAY_SERVICE_NAME}}"
RELAY_SOCKET_PATH="${FIRECRACKER_WATCHDOG_RELAY_SOCKET:-${DEFAULT_RELAY_SOCKET_PATH}}"
RELAY_HEALTH_URL="${FIRECRACKER_WATCHDOG_RELAY_HEALTH_URL:-${DEFAULT_RELAY_HEALTH_URL}}"
SERVICE_LIST="${FIRECRACKER_HEARTBEAT_SERVICE_LIST:-${DEFAULT_SERVICE_LIST}}"
BROKER_SERVICE_TEMPLATE="${FIRECRACKER_HEARTBEAT_BROKER_SERVICE_TEMPLATE:-${DEFAULT_BROKER_SERVICE_TEMPLATE}}"
BROKER_SOCKET_TEMPLATE="${FIRECRACKER_HEARTBEAT_BROKER_SOCKET_TEMPLATE:-${DEFAULT_BROKER_SOCKET_TEMPLATE}}"
BROKER_PORT="${FIRECRACKER_HEARTBEAT_BROKER_PORT:-${DEFAULT_BROKER_PORT}}"
EXTERNAL_CONNECTIVITY_URL="${FIRECRACKER_HEARTBEAT_EXTERNAL_URL:-}"

HEARTBEAT_LOG_FILE=""
HEARTBEAT_STATE_FILE=""

log() {
  printf '%s\n' "$*" >&2
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_writable_dir() {
  local target_dir="$1"

  mkdir -p "${target_dir}" >/dev/null 2>&1 || return 1
  touch "${target_dir}/.write-test" >/dev/null 2>&1 || return 1
  rm -f "${target_dir}/.write-test" >/dev/null 2>&1 || true
  return 0
}

resolve_log_dir() {
  if ensure_writable_dir "${WATCHDOG_LOG_DIR}"; then
    printf '%s' "${WATCHDOG_LOG_DIR}"
    return
  fi

  ensure_writable_dir "${WATCHDOG_FALLBACK_LOG_DIR}" || {
    log "error: unable to write watchdog logs in ${WATCHDOG_LOG_DIR} or ${WATCHDOG_FALLBACK_LOG_DIR}"
    exit 1
  }
  printf '%s' "${WATCHDOG_FALLBACK_LOG_DIR}"
}

load_broker_inventory() {
  if [ -f "${BROKER_INVENTORY_SCRIPT}" ]; then
    # shellcheck disable=SC1090
    . "${BROKER_INVENTORY_SCRIPT}"
  fi
}

collect_broker_rows() {
  if declare -F inventory_rows >/dev/null 2>&1; then
    mapfile -t broker_rows < <(inventory_rows)
  else
    broker_rows=()
  fi

  if [ "${#broker_rows[@]}" -eq 0 ]; then
    broker_rows=("${DEFAULT_BROKER_ROW}")
  fi

  printf '%s\n' "${broker_rows[@]}"
}

service_status() {
  local service_name="$1"

  if cmd_exists systemctl; then
    systemctl is-active "${service_name}" 2>/dev/null || printf 'unknown'
  else
    printf 'unknown'
  fi
}

ping_status() {
  local host_ip="$1"

  if cmd_exists ping && ping -c1 -W1 "${host_ip}" >/dev/null 2>&1; then
    printf 'up'
  else
    printf 'down'
  fi
}

port_status() {
  local host_ip="$1"
  local port_number="$2"

  if cmd_exists nc && nc -z -w2 "${host_ip}" "${port_number}" >/dev/null 2>&1; then
    printf 'open'
  else
    printf 'closed'
  fi
}

find_firecracker_pid() {
  local vm_id="$1"
  local socket_path="$2"
  local process_id=""

  if ! cmd_exists pgrep; then
    return 1
  fi

  process_id="$(pgrep -f "/firecracker --id ${vm_id}" 2>/dev/null | head -n1 || true)"
  if [ -n "${process_id}" ]; then
    printf '%s\n' "${process_id}"
    return 0
  fi

  process_id="$(pgrep -f "firecracker --api-sock ${socket_path}" 2>/dev/null | head -n1 || true)"
  if [ -n "${process_id}" ]; then
    printf '%s\n' "${process_id}"
    return 0
  fi

  return 1
}

health_json() {
  local health_body=""

  if [ -z "${RELAY_HEALTH_URL}" ]; then
    printf '{"status":"disabled"}'
    return
  fi

  health_body="$(curl -s -m2 "${RELAY_HEALTH_URL}" 2>/dev/null || true)"
  if [ -z "${health_body}" ]; then
    printf '{"status":"unreachable"}'
    return
  fi

  if jq -e . >/dev/null 2>&1 <<<"${health_body}"; then
    printf '%s' "${health_body}"
  else
    jq -cn --arg body "${health_body}" '{status:"non_json",body:$body}'
  fi
}

main() {
  cmd_exists jq || { log "error: jq is required"; exit 1; }

  local log_dir=""
  local timestamp=""
  local uptime_seconds="0"
  local load_averages="0 0 0"
  local mem_available_kb="0"
  local mem_total_kb="0"
  local relay_ping_status=""
  local relay_port_status=""
  local relay_process_id=""
  local relay_process_state="unknown"
  local broker_json='[]'
  local service_json='{}'
  local process_json='{}'
  local broker_summary=()
  local broker_row=""
  local broker_id=""
  local broker_ip=""
  local broker_socket=""
  local broker_service_name=""
  local broker_service_status=""
  local broker_ping_status=""
  local broker_port_state=""
  local broker_process_id=""
  local broker_process_state="unknown"
  local external_connectivity="disabled"
  local service_name=""

  log_dir="$(resolve_log_dir)"
  HEARTBEAT_LOG_FILE="${log_dir}/heartbeat.log"
  HEARTBEAT_STATE_FILE="${log_dir}/last_state.json"

  load_broker_inventory
  mapfile -t broker_rows < <(collect_broker_rows)

  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  uptime_seconds="$(awk '{print $1}' /proc/uptime 2>/dev/null || printf '0')"
  load_averages="$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || printf '0 0 0')"
  mem_available_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
  mem_total_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
  uptime_seconds="${uptime_seconds:-0}"
  load_averages="${load_averages:-0 0 0}"
  mem_available_kb="${mem_available_kb:-0}"
  mem_total_kb="${mem_total_kb:-0}"

  IFS=',' read -r -a service_names <<< "${SERVICE_LIST}"
  for service_name in "${service_names[@]}"; do
    service_name="$(printf '%s' "${service_name}" | xargs)"
    [ -n "${service_name}" ] || continue
    service_json="$(jq -c --arg key "${service_name}" --arg value "$(service_status "${service_name}")" '. + {($key):$value}' <<<"${service_json}")"
  done

  for broker_row in "${broker_rows[@]}"; do
    IFS=$'\t' read -r broker_id _ broker_ip _ broker_socket _ _ _ <<<"${broker_row}"
    [ -n "${broker_id}" ] || continue
    [ -n "${broker_ip}" ] || continue
    [ -n "${broker_socket}" ] || broker_socket="$(printf "${BROKER_SOCKET_TEMPLATE}" "${broker_id}")"

    broker_service_name="$(printf "${BROKER_SERVICE_TEMPLATE}" "${broker_id}")"
    broker_service_status="$(service_status "${broker_service_name}")"
    broker_ping_status="$(ping_status "${broker_ip}")"
    broker_port_state="$(port_status "${broker_ip}" "${BROKER_PORT}")"
    broker_process_id="$(find_firecracker_pid "${broker_id}" "${broker_socket}" || true)"

    if [ -n "${broker_process_id}" ] && cmd_exists ps; then
      broker_process_state="$(ps -o stat= -p "${broker_process_id}" 2>/dev/null | tr -d ' ' || printf 'unknown')"
    else
      broker_process_state="unknown"
    fi

    broker_json="$(jq -c \
      --arg id "${broker_id}" \
      --arg ip "${broker_ip}" \
      --arg ping "${broker_ping_status}" \
      --arg port "${broker_port_state}" \
      --arg service "${broker_service_status}" \
      --arg pid "${broker_process_id}" \
      --arg state "${broker_process_state}" \
      '. + [{id:$id,ip:$ip,ping:$ping,port_9092:$port,service:$service,firecracker_pid:$pid,firecracker_state:$state}]' <<<"${broker_json}")"

    service_json="$(jq -c --arg key "${broker_service_name}" --arg value "${broker_service_status}" '. + {($key):$value}' <<<"${service_json}")"
    process_json="$(jq -c --arg id "${broker_id}" --arg pid "${broker_process_id}" --arg state "${broker_process_state}" '. + {($id):{pid:$pid,state:$state}}' <<<"${process_json}")"

    broker_summary+=("${broker_id}:${broker_ping_status}:${broker_port_state}:${broker_service_status}:${broker_process_state}")
  done

  relay_ping_status="$(ping_status "${RELAY_VM_IP}")"
  relay_port_status="$(port_status "${RELAY_VM_IP}" "${RELAY_VM_PORT}")"
  relay_process_id="$(find_firecracker_pid relay "${RELAY_SOCKET_PATH}" || true)"
  if [ -n "${relay_process_id}" ] && cmd_exists ps; then
    relay_process_state="$(ps -o stat= -p "${relay_process_id}" 2>/dev/null | tr -d ' ' || printf 'unknown')"
  fi

  if [ -n "${EXTERNAL_CONNECTIVITY_URL}" ]; then
    external_connectivity="$(curl -s -m5 -o /dev/null -w '%{http_code}' "${EXTERNAL_CONNECTIVITY_URL}" 2>/dev/null || true)"
    [ -n "${external_connectivity}" ] || external_connectivity="failed"
  fi

  printf '%s uptime=%ss load=%s mem=%s/%skB relay_vm=%s:%s kafka_brokers=%s\n' \
    "${timestamp}" "${uptime_seconds}" "${load_averages}" "${mem_available_kb}" "${mem_total_kb}" \
    "${relay_ping_status}" "${relay_port_status}" "$(IFS=';'; echo "${broker_summary[*]:-none}")" >> "${HEARTBEAT_LOG_FILE}"

  jq -cn \
    --arg timestamp "${timestamp}" \
    --arg uptime_seconds "${uptime_seconds}" \
    --arg load "${load_averages}" \
    --arg mem_available "${mem_available_kb}" \
    --arg mem_total "${mem_total_kb}" \
    --arg relay_ping "${relay_ping_status}" \
    --arg relay_port "${relay_port_status}" \
    --arg relay_service "$(service_status "${RELAY_SERVICE_NAME}")" \
    --arg relay_pid "${relay_process_id}" \
    --arg relay_state "${relay_process_state}" \
    --argjson brokers "${broker_json}" \
    --argjson services "${service_json}" \
    --argjson processes "${process_json}" \
    --argjson health "$(health_json)" \
    --arg external_connectivity "${external_connectivity}" \
    '{
      timestamp: $timestamp,
      uptime_seconds: ($uptime_seconds | tonumber),
      load: $load,
      memory: {available_kb: ($mem_available | tonumber), total_kb: ($mem_total | tonumber)},
      vms: {
        relay: {ping: $relay_ping, port_8080: $relay_port, service: $relay_service, firecracker_pid: $relay_pid, firecracker_state: $relay_state},
        kafka_brokers: $brokers
      },
      services: $services,
      firecracker_process: {brokers: $processes, relay: {pid: $relay_pid, state: $relay_state}},
      health_endpoint: $health,
      external_connectivity: $external_connectivity
    }' > "${HEARTBEAT_STATE_FILE}"
}

main "$@"
