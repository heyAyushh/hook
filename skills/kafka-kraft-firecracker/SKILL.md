---
name: kafka-kraft-firecracker
description: >
  Provision and operate Apache Kafka in KRaft mode inside a Firecracker microVM
  without Docker, including host networking, guest bootstrap, systemd service,
  and security checks. Use when setting up a lightweight isolated Kafka broker
  for internal pipelines such as hook serve/relay/smash Kafka core transport.
---

# Kafka KRaft on Firecracker

## Scope

Use this skill to deploy single-node Kafka KRaft inside a Firecracker VM with no ZooKeeper.

## Workflow

1. Validate host prerequisites.
2. Configure Firecracker host networking (tap + NAT).
3. Boot a Linux guest in Firecracker.
4. Run guest bootstrap script to install Kafka KRaft and systemd unit.
5. Validate broker health and KRaft metadata state.
6. Apply hardening checks before exposing any listener.

## 1) Host Prerequisites

- Linux host with `/dev/kvm`
- `firecracker` binary and kernel image available
- Optional launcher script for jailer flow: `firecracker/runtime/launch.sh`
- `ip`, `iptables`, `sysctl`, `curl`, `tar` on host
- Guest OS with systemd and Java-capable package manager

Quick checks:

```bash
test -e /dev/kvm && echo "kvm ok"
firecracker --version
```

## 2) Host Network Setup

Use:

```bash
skills/kafka-kraft-firecracker/scripts/setup-firecracker-kafka-tap.sh
```

Defaults:

- TAP: `tap-kafka0`
- Host IP: `172.16.40.1/24`
- Guest IP: `172.16.40.2`
- Outbound iface: auto-detected from default route

## 3) Boot Firecracker VM

Use the repository launch helper and set guest networking in the config to match the TAP values:

```bash
scripts/run-firecracker.sh --config out/firecracker/firecracker-config.json
```

Launch behavior:

- If repo launcher `firecracker/runtime/launch.sh` is executable, the helper uses it (`relay` profile by default).
- If repo launcher is missing, helper falls back to `firecracker` from `PATH`.
- If `logger.log_path` points to a non-writable directory, the helper rewrites a temporary runtime config and logs under `/tmp/firecracker` by default.

Override knobs:

- `--launcher <path>` or `FIRECRACKER_LAUNCHER_PATH`
- `--launcher-profile <name>` or `FIRECRACKER_LAUNCHER_PROFILE`
- `--no-launcher` to force direct Firecracker execution
- `--fallback-log-dir <path>` or `FIRECRACKER_FALLBACK_LOG_DIR`

## 4) Install Kafka KRaft in Guest

Run inside guest as root:

```bash
cp /path/to/repo/skills/kafka-kraft-firecracker/scripts/bootstrap-kafka-kraft.sh /tmp/bootstrap-kafka-kraft.sh
chmod +x /tmp/bootstrap-kafka-kraft.sh
bash /tmp/bootstrap-kafka-kraft.sh
```

If the script is baked into the guest image, run it directly from that path.

Key env vars:

- `KAFKA_VERSION` (default `4.0.0`)
- `KAFKA_SCALA_VERSION` (default `2.13`)
- `KAFKA_NODE_ID` (default `1`)
- `KAFKA_BROKER_PORT` (default `9092`)
- `KAFKA_CONTROLLER_PORT` (default `9093`)
- `KAFKA_QUORUM_VOTERS` (default `1@127.0.0.1:9093`)
- `KAFKA_ADVERTISED_HOST` (default `127.0.0.1`; set to guest TAP IP, e.g. `172.16.40.2`, so the relay can reach the broker from the host)
- `KAFKA_LISTEN_ADDRESS` (default `0.0.0.0`; bind address for broker and controller listeners)
- `KAFKA_CLUSTER_ID` (optional; auto-generated if unset)

## 5) Validate

Inside guest:

```bash
systemctl status kafka-kraft --no-pager
journalctl -u kafka-kraft -n 100 --no-pager
/opt/kafka/bin/kafka-topics.sh --bootstrap-server 127.0.0.1:9092 --list
```

Expected:

- service active
- no ZooKeeper references
- controller quorum initialized

## 6) Hardening

- Keep controller listener private (`9093` not internet-exposed).
- Prefer Tailscale/private NIC for broker listener.
- Restrict host firewall to trusted CIDRs only.
- Set `auto.create.topics.enable=false` unless required.
- Run Kafka as dedicated non-root user (`kafka`).
- Keep VM snapshot/backups for `KAFKA_LOG_DIRS`.

## 7) Host Broker Proxy Integration

After the Kafka VM is running, the relay and consumers need a host-side port to reach the broker. Use the broker inventory + proxy-mux pattern from `firecracker/runtime/broker_inventory.sh` and `firecracker/systemd/proxy-mux.sh`.

### Broker Inventory

`firecracker/runtime/broker_inventory.sh` defines the broker fleet. It reads `/etc/firecracker/brokers.json` if present; otherwise falls back to a built-in default row:

```
id=kafka  node_id=1  ip=172.30.0.10  tap=tap-kafka  socket=/tmp/kafka-fc.sock
host_proxy_port=9092  config=/opt/firecracker/kafka/config.json  rootfs=...
```

Override the inventory file path with `FC_BROKER_INVENTORY`.

Example `/etc/firecracker/brokers.json`:

```json
{
  "brokers": [
    {
      "id": "kafka",
      "node_id": 1,
      "ip": "172.16.40.2",
      "tap": "tap-kafka0",
      "socket": "/tmp/kafka-fc.sock",
      "host_proxy_port": 9092,
      "config": "/opt/firecracker/kafka/config.json",
      "rootfs": "/opt/firecracker/kafka/rootfs.ext4"
    }
  ]
}
```

### Proxy Mux

`firecracker/systemd/proxy-mux.sh` sources the broker inventory and can start `socat` forwards for the relay VM and brokers:

- Relay proxy: `TCP-LISTEN:9445` → `172.30.0.20:8080` (override via `FIRECRACKER_RELAY_VM_IP`/`FIRECRACKER_RELAY_VM_PORT`)
- Broker proxies: `TCP-LISTEN:<host_proxy_port>` → `<broker_ip>:9092` (bound to `127.0.0.1` by default)

Proxy forwarding is disabled by default. Enable with:

- `FIRECRACKER_ENABLE_RELAY_PROXY=true`
- `FIRECRACKER_ENABLE_BROKER_PROXIES=true`

Requires `socat` only when either proxy mode is enabled. Managed by `firecracker/systemd/firecracker-proxy-mux.service`.

Env overrides (set in `/etc/firecracker/proxy-mux.env`):

- `FIRECRACKER_BROKER_INVENTORY_SCRIPT` (path to broker_inventory.sh)
- `FIRECRACKER_ENABLE_RELAY_PROXY` (default `false`)
- `FIRECRACKER_ENABLE_BROKER_PROXIES` (default `false`)
- `FIRECRACKER_RELAY_PROXY_PORT` (default `9445`)
- `FIRECRACKER_RELAY_VM_IP` (default `172.30.0.20`)
- `FIRECRACKER_RELAY_VM_PORT` (default `8080`)
- `FIRECRACKER_BROKER_PROXY_BIND_HOST` (default `127.0.0.1`)
- `FIRECRACKER_BROKER_TARGET_PORT` (default `9092`)

## 8) Watchdog and Health Monitoring

The watchdog stack runs on the host and monitors relay + broker VMs with optional alerting.

### Local Watchdog

`firecracker/watchdog/watchdog.sh` runs on a timer (`firecracker-watchdog.timer`, `OnBootSec=2min / OnUnitActiveSec=1min`) and:

- Checks each required service via `systemctl is-active`
- Port-probes each broker (`BROKER_PORT` default `9092`) and the relay (`172.30.0.20:8080`)
- Detects stuck Firecracker processes (D/Z state) and kills+restarts them
- Optionally checks relay HTTP health URL if `FIRECRACKER_WATCHDOG_RELAY_HEALTH_URL` is set
- Optionally checks a chisel tunnel endpoint if `FIRECRACKER_WATCHDOG_CHISEL_HOST_PORT` is set
- Optionally runs `kcat` Kafka metadata check if `FIRECRACKER_WATCHDOG_ENABLE_KAFKA_METADATA_CHECK=true`
- Calls `heartbeat.sh` each cycle to write `last_state.json`

Configuration lives in `/etc/firecracker/watchdog.env` (copy from `firecracker/watchdog/watchdog.env.example`). Defaults:

- Required services: `firecracker-network.service,firecracker@relay.service`
- Relay health URL: disabled (empty)
- Chisel check: disabled (empty)
- Kafka metadata check: disabled (`false`)
- Restart delay: `5s`
- Log dir: `/var/log/firecracker/watchdog` (fallback `/tmp/firecracker-watchdog`)

### Alerting

`firecracker/watchdog/alert.sh` is sourced by the watchdog, heartbeat, and external checkers. It provides `alert_emit <severity> <event_key> <message>` with:

- 300-second per-event cooldown (state in `/var/lib/firecracker-watchdog`)
- Webhook delivery if `ALERT_WEBHOOK_URL` is set (optional bearer token via `ALERT_WEBHOOK_BEARER_TOKEN`)
- Email delivery if `ALERT_EMAIL_TO` is set (via `sendmail` or `mail`)
- Log line to `/var/log/firecracker/alerts.log` and `logger`

Configure in `/etc/firecracker/alerts.env` (copy from `firecracker/watchdog/alerts.env.example`).

### Heartbeat

`firecracker/watchdog/heartbeat.sh` is called by the watchdog each cycle. It writes a JSON state snapshot to `{log_dir}/last_state.json` covering relay ping/port/service/process state, per-broker state, memory, load, and optional external connectivity. Requires `jq`.

Quick status: `firecracker/watchdog/status.sh`

### External Checkers (separate host)

Run on a different host to detect outages from outside:

- `external-blackbox.sh` / `external-blackbox.service` + timer: probes `POST /webhook/github` (expect `401`) and `GET /` (expect `200`) against `BLACKBOX_BASE_URL`
- `external-chisel-check.sh` / `external-chisel-check.service` + timer: checks a chisel tunnel port

Copy env files from `firecracker/watchdog/external-blackbox.env.example` → `/etc/firecracker/external-blackbox.env` and `chisel-check.env.example` → `/etc/firecracker/chisel-check.env` on the checker host.

### Boot/Shutdown Diagnostics

- `firecracker-boot-logger.service`: runs `firecracker/watchdog/boot-logger.sh` on host boot; logs gap since last heartbeat
- `firecracker-shutdown-logger.service`: runs `firecracker/watchdog/shutdown-logger.sh` on host shutdown
- `kernel-kmsg-capture.service`: captures kernel ring buffer entries via `kernel-kmsg-capture.py`
- `pstore-collect.service`: collects pstore/efi crash dumps on boot

## Troubleshooting

- `curl/curl.h` or librdkafka build issues are host-client side, not guest Kafka runtime.
- If startup fails after config changes, re-check `node.id` and `controller.quorum.voters` consistency.
- If metadata format issues appear, verify `meta.properties` and cluster ID under log dirs.
- If launch fails with "configured launcher is not executable", fix launcher path or use `--no-launcher`.
- If host log path is not writable, set `--fallback-log-dir` to a writable host directory.
- If watchdog log dir is not writable, logs fall back to `/tmp/firecracker-watchdog`.
- Proxy-mux exits cleanly if both `FIRECRACKER_ENABLE_RELAY_PROXY` and `FIRECRACKER_ENABLE_BROKER_PROXIES` are false — this is correct; no proxies means no `socat` required.

Detailed commands: `skills/kafka-kraft-firecracker/references/kraft-firecracker-runbook.md`.
