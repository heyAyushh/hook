# First-Time Setup Guide

Walk a user through setting up the `hook serve/relay/smash` stack from scratch. Use `AskUserQuestion` for each phase. Collect all answers before generating config files.

---

## Security-First Defaults

- Expose exactly one public service: `hook serve` (HTTP ingress)
- Keep OpenClaw private (`localhost` or tailnet-only)
- All source HMAC secrets are required — serve fails closed if any are missing

---

## Phase 1: Scope

Ask:
- **Which sources?** GitHub only, Linear only, or both?
- **GitHub account type?** Personal or organization?
- **App profile?** Use `default-openclaw` or a custom app name?

---

## Phase 2: Infrastructure

Ask:
- **Where will `hook serve` run?** Local machine, VPS, or existing server?
- **Is OpenClaw colocated?** Same host as `hook serve` (localhost) or a separate node?
- **Kafka?** Use an existing broker, Firecracker-hosted Kafka, or need to set one up?
- **Public ingress?** Tailscale Funnel (recommended), reverse proxy (nginx/caddy), or other?
- **Public relay base URL?** e.g. `https://your-machine.tail-net.ts.net`

---

## Phase 3: GitHub Setup (if selected)

Ask:
- **GitHub App or per-repo webhook?** App is recommended for multi-repo coverage.
- **GitHub App name?** e.g. `openclaw-agent` (becomes `name[bot]` identity)
- **Webhook URL?** Default: `{public-relay-base-url}/webhook/github`
- **App owner?** Personal account or organization slug

If GitHub App selected, guide through creation using [github-hooks.md](github-hooks.md). Collect:
- `GITHUB_APP_ID`
- `GITHUB_APP_PRIVATE_KEY` (path to `.pem`)
- `GITHUB_INSTALLATION_ID`

---

## Phase 4: Linear Setup (if selected)

Ask:
- **Linear agent user already created?** If yes, collect API key and user ID. If no, guide through creating the service account (see [linear-hooks.md](linear-hooks.md)).
- **Which team(s)?** Team key(s) the agent should monitor.
- **Webhook URL?** Default: `{public-relay-base-url}/webhook/linear`

---

## Phase 5: OpenClaw

Ask:
- **OpenClaw already running?** If no, note it is a prerequisite.
- **OpenClaw URL?** Default: `http://127.0.0.1:18789`
- **Hooks endpoint path?** Default: `/hooks/agent`

---

## Phase 6: Secrets

Do NOT generate secrets — let the user generate them:

```bash
openssl rand -hex 32   # HMAC_SECRET_GITHUB
openssl rand -hex 32   # HMAC_SECRET_LINEAR
openssl rand -hex 32   # OPENCLAW_WEBHOOK_TOKEN
```

Collect:
- `HMAC_SECRET_GITHUB` (new or existing)
- `HMAC_SECRET_LINEAR` (new or existing)
- `OPENCLAW_WEBHOOK_TOKEN` (must match OpenClaw `hooks.token`)
- `KAFKA_BROKERS` (e.g. `127.0.0.1:9092`)
- `KAFKA_SECURITY_PROTOCOL` (`ssl` for production, `plaintext` for dev)
- TLS paths if SSL: `KAFKA_TLS_CERT`, `KAFKA_TLS_KEY`, `KAFKA_TLS_CA`

---

## Phase 7: Generate

After collecting all answers, generate these files:

### 1. `.env`

```bash
# Sources
RELAY_ENABLED_SOURCES=github,linear
HMAC_SECRET_GITHUB=<generated>
HMAC_SECRET_LINEAR=<generated>

# Kafka
KAFKA_BROKERS=127.0.0.1:9092
KAFKA_SECURITY_PROTOCOL=plaintext
KAFKA_ALLOW_PLAINTEXT=true

# OpenClaw output
OPENCLAW_WEBHOOK_TOKEN=<generated>

# Optional: GitHub App for outbound calls
GITHUB_APP_ID=
GITHUB_APP_PRIVATE_KEY=/etc/relay/secrets/github-app.pem
GITHUB_INSTALLATION_ID=

# Optional: Linear agent user
LINEAR_AGENT_API_KEY=
LINEAR_AGENT_USER_ID=
```

### 2. `apps/<app>/contract.toml`

Generate based on selected sources and adapters. Start from `apps/default-openclaw/contract.toml` and customize app ID, profile name, and OpenClaw URL.

### 3. OpenClaw transform modules

Generate `~/.openclaw/hooks/transforms/github.ts` and/or `linear.ts` based on selected sources. See [openclaw-relay.md](openclaw-relay.md#transform-modules) for minimal templates.

---

## Phase 8: Post-Generation Checklist

Print a checklist of remaining manual steps:

```
Setup checklist:
[ ] Install hook CLI: cargo install --path tools/hook
[ ] Set up Kafka (see skills/kafka-kraft-firecracker/ for Firecracker option)
[ ] Create Kafka topics:
      KAFKA_BOOTSTRAP=127.0.0.1:9092 SOURCES="github linear" \
        skills/kafka-topic-setup/scripts/create-hook-topics.sh
[ ] Validate contract: hook validate --app default-openclaw
[ ] Create GitHub App (see github-hooks.md)
      - Webhook URL: {public-relay-base-url}/webhook/github
      - Secret: value of HMAC_SECRET_GITHUB
      - Install on account/org
[ ] Create Linear webhook (Settings > API > Webhooks)
      - URL: {public-relay-base-url}/webhook/linear
      - Secret: value of HMAC_SECRET_LINEAR
[ ] Copy .env to /etc/relay/.env (or your deployment location)
[ ] Copy transform modules to ~/.openclaw/hooks/transforms/
[ ] Configure OpenClaw hooks.token = OPENCLAW_WEBHOOK_TOKEN value
[ ] Start hook serve: hook serve --app default-openclaw
[ ] Verify: curl http://localhost:8080/ready
[ ] Start hook relay: hook relay --topics webhooks.github,webhooks.linear --output-topic webhooks.core
[ ] Start hook smash: hook smash --app default-openclaw
[ ] Expose via Tailscale: tailscale funnel --bg 8080 (see tailscale.md)
[ ] Verify OpenClaw is NOT internet-exposed (bound to localhost only)
[ ] Send smoke test (see boot.md)
```

---

## Question Flow Rules

- Ask one phase at a time
- Skip phases for unselected sources
- Use sensible defaults — only ask when the choice matters
- If the user says "defaults" or "just set it up", use:
  - Both sources (GitHub + Linear)
  - Colocated OpenClaw (localhost:18789)
  - Tailscale Funnel for ingress
  - App ID: `default-openclaw`
  - Plaintext Kafka for development, TLS for production
