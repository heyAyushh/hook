#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TAP_NAME="${TAP_NAME:-tap-kafka0}"
HOST_CIDR="${HOST_CIDR:-172.16.40.1/24}"
GUEST_CIDR="${GUEST_CIDR:-172.16.40.2/24}"
UPLINK_IFACE="${UPLINK_IFACE:-}"

log() {
  printf '%s\n' "$*" >&2
}

die() {
  log "error: $*"
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "run as root"
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "missing command: ${cmd}"
}

auto_detect_uplink() {
  if [ -n "${UPLINK_IFACE}" ]; then
    return
  fi

  UPLINK_IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
  [ -n "${UPLINK_IFACE}" ] || die "could not auto-detect UPLINK_IFACE"
}

ensure_tap() {
  if ! ip link show "${TAP_NAME}" >/dev/null 2>&1; then
    ip tuntap add dev "${TAP_NAME}" mode tap
  fi

  if ! ip addr show dev "${TAP_NAME}" | grep -q "${HOST_CIDR%%/*}"; then
    ip addr add "${HOST_CIDR}" dev "${TAP_NAME}" || true
  fi

  ip link set "${TAP_NAME}" up
}

enable_forwarding() {
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

ensure_nat_rules() {
  local guest_net
  guest_net="${GUEST_CIDR%.*}.0/24"

  iptables -C FORWARD -i "${TAP_NAME}" -o "${UPLINK_IFACE}" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "${TAP_NAME}" -o "${UPLINK_IFACE}" -j ACCEPT

  iptables -C FORWARD -i "${UPLINK_IFACE}" -o "${TAP_NAME}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "${UPLINK_IFACE}" -o "${TAP_NAME}" -m state --state RELATED,ESTABLISHED -j ACCEPT

  iptables -t nat -C POSTROUTING -s "${guest_net}" -o "${UPLINK_IFACE}" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "${guest_net}" -o "${UPLINK_IFACE}" -j MASQUERADE
}

main() {
  require_root
  require_cmd ip
  require_cmd iptables
  require_cmd sysctl

  auto_detect_uplink
  ensure_tap
  enable_forwarding
  ensure_nat_rules

  log "tap interface ready"
  log "tap=${TAP_NAME} host=${HOST_CIDR} guest=${GUEST_CIDR} uplink=${UPLINK_IFACE}"
}

main "$@"
