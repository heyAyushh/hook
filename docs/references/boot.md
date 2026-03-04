# Boot Verification

Pre-flight checks for the `hook serve/relay/smash` stack. Run in order — stop at the first failure.

---

## 1. Binary

```bash
# Verify hook CLI is installed
command -v hook && hook --version || echo "FAIL: hook not installed"

# Install from source if missing:
cargo install --path tools/hook
```

---

## 2. Environment

Required variables for the default stack:

```bash
REQUIRED_VARS=(
  KAFKA_BROKERS
  HMAC_SECRET_GITHUB
  HMAC_SECRET_LINEAR
  OPENCLAW_WEBHOOK_TOKEN
)

for var in "${REQUIRED_VARS[@]}"; do
  [ -n "${!var:-}" ] && echo "  OK: $var" || echo "FAIL: $var not set"
done
```

For TLS, also check:

```bash
TLS_VARS=(KAFKA_TLS_CERT KAFKA_TLS_KEY KAFKA_TLS_CA)
for var in "${TLS_VARS[@]}"; do
  [ -n "${!var:-}" ] || echo "FAIL: $var not set"
  [ -f "${!var:-/dev/null}" ] || echo "FAIL: ${!var} not a readable file"
done
```

---

## 3. Contract Validation

```bash
# Validate contract before starting
hook validate --app default-openclaw
echo "Exit $?: contract valid"
```

A non-zero exit with an error message means the contract has a misconfiguration. Fix before starting.

---

## 4. Kafka Connectivity

```bash
# Check Kafka broker is reachable (plaintext example)
BOOTSTRAP="${KAFKA_BROKERS:-127.0.0.1:9092}"
timeout 3 bash -c "echo > /dev/tcp/${BOOTSTRAP%:*}/${BOOTSTRAP##*:}" \
  && echo "OK: Kafka reachable at $BOOTSTRAP" \
  || echo "FAIL: Kafka not reachable at $BOOTSTRAP"
```

---

## 5. Kafka Topics

```bash
# List topics (requires kafka-topics.sh or kcat)
/opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "${KAFKA_BROKERS:-127.0.0.1:9092}" \
  --list | grep webhooks

# Expected topics:
# webhooks.github
# webhooks.linear
# webhooks.core
# webhooks.dlq
```

If topics are missing, create them:

```bash
KAFKA_BOOTSTRAP="${KAFKA_BROKERS:-127.0.0.1:9092}" \
SOURCES="github linear" \
  skills/kafka-topic-setup/scripts/create-hook-topics.sh
```

---

## 6. Serve Health Check

After starting `hook serve --app default-openclaw`:

```bash
# Liveness
curl -sf http://localhost:8080/health && echo "OK: serve liveness"

# Readiness (Kafka producer connected)
curl -sf http://localhost:8080/ready && echo "OK: serve ready"
```

`/ready` returns `503` if the Kafka producer is not connected. Wait for `200` before routing traffic.

---

## 7. End-to-End Smoke Test

```bash
BODY='{"zen":"Keep it logically awesome."}'
SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$HMAC_SECRET_GITHUB" | cut -d' ' -f2)"

curl -sf -X POST http://localhost:8080/webhook/github \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -H "X-GitHub-Delivery: boot-check-$(date +%s)" \
  -H "X-Hub-Signature-256: $SIG" \
  -d "$BODY" && echo "OK: webhook accepted"
```

Expected HTTP 200. Check serve logs for `published` message.

---

## Quick Boot Script

```bash
#!/usr/bin/env bash
set -euo pipefail
FAIL=0
check() { eval "$2" >/dev/null 2>&1 && printf "  OK: %s\n" "$1" || { printf "FAIL: %s\n" "$1"; FAIL=1; }; }

echo "=== Binary ==="
check "hook installed"       "command -v hook"

echo "=== Env ==="
check "KAFKA_BROKERS"              "[ -n \"${KAFKA_BROKERS:-}\" ]"
check "HMAC_SECRET_GITHUB"         "[ -n \"${HMAC_SECRET_GITHUB:-}\" ]"
check "HMAC_SECRET_LINEAR"         "[ -n \"${HMAC_SECRET_LINEAR:-}\" ]"
check "OPENCLAW_WEBHOOK_TOKEN"     "[ -n \"${OPENCLAW_WEBHOOK_TOKEN:-}\" ]"

echo "=== Contract ==="
check "contract valid"  "hook validate --app default-openclaw"

echo "=== Kafka ==="
BOOTSTRAP="${KAFKA_BROKERS:-127.0.0.1:9092}"
check "broker reachable" "timeout 3 bash -c 'echo > /dev/tcp/${BOOTSTRAP%:*}/${BOOTSTRAP##*:}'"

[ $FAIL -eq 0 ] && echo "All checks passed." || echo "Fix failures above before starting."
exit $FAIL
```

---

## Order of Operations

1. Run boot checks above
2. Start Kafka (if not already running)
3. Create topics if missing
4. Start `hook serve --app default-openclaw`
5. Wait for `/ready` → `200`
6. Start `hook relay --topics webhooks.github,webhooks.linear --output-topic webhooks.core`
7. Start `hook smash --app default-openclaw`
8. Send smoke test payload
9. Expose via reverse proxy or Tailscale Funnel (see [tailscale.md](tailscale.md))

Do not expose the webhook URL until `/ready` returns `200`.
