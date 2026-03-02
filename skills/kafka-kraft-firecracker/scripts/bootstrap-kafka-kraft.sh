#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

KAFKA_VERSION="${KAFKA_VERSION:-4.0.0}"
KAFKA_SCALA_VERSION="${KAFKA_SCALA_VERSION:-2.13}"
KAFKA_USER="${KAFKA_USER:-kafka}"
KAFKA_GROUP="${KAFKA_GROUP:-kafka}"
KAFKA_INSTALL_DIR="${KAFKA_INSTALL_DIR:-/opt/kafka}"
KAFKA_CONFIG_DIR="${KAFKA_CONFIG_DIR:-/etc/kafka/kraft}"
KAFKA_DATA_DIR="${KAFKA_DATA_DIR:-/var/lib/kafka/kraft-combined-logs}"
KAFKA_NODE_ID="${KAFKA_NODE_ID:-1}"
KAFKA_BROKER_PORT="${KAFKA_BROKER_PORT:-9092}"
KAFKA_CONTROLLER_PORT="${KAFKA_CONTROLLER_PORT:-9093}"
KAFKA_LISTEN_ADDRESS="${KAFKA_LISTEN_ADDRESS:-0.0.0.0}"
KAFKA_ADVERTISED_HOST="${KAFKA_ADVERTISED_HOST:-127.0.0.1}"
KAFKA_QUORUM_VOTERS="${KAFKA_QUORUM_VOTERS:-1@127.0.0.1:9093}"
KAFKA_ARCHIVE_URL="${KAFKA_ARCHIVE_URL:-https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz}"
CLUSTER_ID="${KAFKA_CLUSTER_ID:-}"

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

install_java_if_missing() {
  if command -v java >/dev/null 2>&1; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends openjdk-21-jre-headless curl ca-certificates tar
    return
  fi

  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache openjdk21-jre curl ca-certificates tar bash coreutils
    return
  fi

  die "java not found and no supported package manager detected"
}

ensure_user_group() {
  if ! getent group "${KAFKA_GROUP}" >/dev/null 2>&1; then
    groupadd --system "${KAFKA_GROUP}"
  fi

  if ! id "${KAFKA_USER}" >/dev/null 2>&1; then
    useradd --system --gid "${KAFKA_GROUP}" --home-dir /nonexistent --shell /usr/sbin/nologin "${KAFKA_USER}"
  fi
}

install_kafka() {
  local tmp_archive
  tmp_archive="$(mktemp /tmp/kafka-kraft.XXXXXX.tgz)"

  log "downloading ${KAFKA_ARCHIVE_URL}"
  curl -fsSL "${KAFKA_ARCHIVE_URL}" -o "${tmp_archive}"

  rm -rf "${KAFKA_INSTALL_DIR}"
  mkdir -p "${KAFKA_INSTALL_DIR}"
  tar -xzf "${tmp_archive}" --strip-components=1 -C "${KAFKA_INSTALL_DIR}"
  rm -f "${tmp_archive}"

  chown -R "${KAFKA_USER}:${KAFKA_GROUP}" "${KAFKA_INSTALL_DIR}"
}

write_kraft_config() {
  mkdir -p "${KAFKA_CONFIG_DIR}"
  mkdir -p "${KAFKA_DATA_DIR}"
  chown -R "${KAFKA_USER}:${KAFKA_GROUP}" "${KAFKA_CONFIG_DIR}" "${KAFKA_DATA_DIR}"

  cat > "${KAFKA_CONFIG_DIR}/server.properties" <<EOF_CFG
process.roles=broker,controller
node.id=${KAFKA_NODE_ID}
controller.quorum.voters=${KAFKA_QUORUM_VOTERS}

listeners=PLAINTEXT://${KAFKA_LISTEN_ADDRESS}:${KAFKA_BROKER_PORT},CONTROLLER://${KAFKA_LISTEN_ADDRESS}:${KAFKA_CONTROLLER_PORT}
advertised.listeners=PLAINTEXT://${KAFKA_ADVERTISED_HOST}:${KAFKA_BROKER_PORT}
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT

log.dirs=${KAFKA_DATA_DIR}
num.partitions=3
default.replication.factor=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
min.insync.replicas=1
group.initial.rebalance.delay.ms=0
auto.create.topics.enable=false
delete.topic.enable=true
EOF_CFG

  chown "${KAFKA_USER}:${KAFKA_GROUP}" "${KAFKA_CONFIG_DIR}/server.properties"
  chmod 0640 "${KAFKA_CONFIG_DIR}/server.properties"
}

format_storage() {
  if [ -z "${CLUSTER_ID}" ]; then
    CLUSTER_ID="$("${KAFKA_INSTALL_DIR}/bin/kafka-storage.sh" random-uuid)"
  fi

  log "formatting KRaft storage with cluster id ${CLUSTER_ID}"
  "${KAFKA_INSTALL_DIR}/bin/kafka-storage.sh" format \
    -t "${CLUSTER_ID}" \
    -c "${KAFKA_CONFIG_DIR}/server.properties" \
    --ignore-formatted
}

write_systemd_unit() {
  cat > /etc/systemd/system/kafka-kraft.service <<EOF_UNIT
[Unit]
Description=Apache Kafka (KRaft)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${KAFKA_USER}
Group=${KAFKA_GROUP}
ExecStart=${KAFKA_INSTALL_DIR}/bin/kafka-server-start.sh ${KAFKA_CONFIG_DIR}/server.properties
ExecStop=${KAFKA_INSTALL_DIR}/bin/kafka-server-stop.sh
Restart=always
RestartSec=5
LimitNOFILE=200000
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
EOF_UNIT
}

start_service() {
  systemctl daemon-reload
  systemctl enable --now kafka-kraft
}

main() {
  require_root
  require_cmd curl
  require_cmd tar
  install_java_if_missing
  ensure_user_group
  install_kafka
  write_kraft_config
  format_storage
  write_systemd_unit
  start_service

  log "kafka-kraft installed and started"
  log "validate with: systemctl status kafka-kraft --no-pager"
  log "list topics with: ${KAFKA_INSTALL_DIR}/bin/kafka-topics.sh --bootstrap-server 127.0.0.1:${KAFKA_BROKER_PORT} --list"
}

main "$@"
