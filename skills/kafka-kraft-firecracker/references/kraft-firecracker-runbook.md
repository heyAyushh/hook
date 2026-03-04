# Kafka KRaft on Firecracker Runbook

## Goal

Run a single-node Kafka broker in KRaft mode (`process.roles=broker,controller`) inside a Firecracker microVM.

## Host Sequence

1. Prepare networking:

```bash
sudo TAP_NAME=tap-kafka0 HOST_CIDR=172.16.40.1/24 GUEST_CIDR=172.16.40.2/24 \
  skills/kafka-kraft-firecracker/scripts/setup-firecracker-kafka-tap.sh
```

2. Prepare VM config from your template:

- assign `host_dev_name` to `tap-kafka0`
- guest MAC should match your guest network config
- keep rootfs read-only if possible

3. Boot Firecracker with the repository helper:

```bash
scripts/run-firecracker.sh --config out/firecracker/firecracker-config.json
```

Optional host-specific launcher override:

```bash
scripts/run-firecracker.sh \
  --config out/firecracker/firecracker-config.json \
  --launcher /opt/hook-serve/firecracker/runtime/launch.sh \
  --launcher-profile relay
```

Portable direct execution mode:

```bash
scripts/run-firecracker.sh \
  --config out/firecracker/firecracker-config.json \
  --no-launcher
```

Notes:

- If launcher path is absent and not explicitly configured, helper falls back to `firecracker` from `PATH`.
- If configured `logger.log_path` is not writable, helper rewrites a temporary runtime config to use `/tmp/firecracker` (or `--fallback-log-dir`).
- Host proxy-mux is opt-in. Set `FIRECRACKER_ENABLE_RELAY_PROXY=true` and/or `FIRECRACKER_ENABLE_BROKER_PROXIES=true` in `/etc/firecracker/proxy-mux.env` only if you need socat forwards.

## Guest Sequence

1. Copy bootstrap script into guest.
2. Run as root:

```bash
KAFKA_VERSION=4.0.0 \
KAFKA_ADVERTISED_HOST=172.16.40.2 \
sudo bash bootstrap-kafka-kraft.sh
```

3. Validate:

```bash
systemctl is-active kafka-kraft
journalctl -u kafka-kraft -n 100 --no-pager
/opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server 127.0.0.1:9092 describe --status
```

## Security Controls

- Do not expose controller listener (`9093`) publicly.
- Restrict broker listener (`9092`) to private networks/Tailscale.
- Use host firewall allowlists.
- Keep logs and snapshots for fast recovery.
- Keep Kafka user non-root.

## Common Failure Modes

- `node.id` mismatch against `controller.quorum.voters`
- stale or inconsistent metadata in log dir after reformat
- guest has wrong default route or DNS due to tap/NAT misconfiguration
- firewall blocks `9092` from relay/consumers
- non-writable host log directory in `logger.log_path` (set `--fallback-log-dir`)
