# Linear Webhook Source

## How It Works

`hook serve` accepts Linear webhook deliveries at `/webhook/linear`. Each request is validated before the payload is processed:

1. Read `HMAC_SECRET_LINEAR` from env — reject at startup if missing
2. Compute HMAC-SHA256 over the raw request body
3. Compare to `Linear-Signature: <hex>` header using constant-time comparison
4. Validate payload timestamp: reject if older than `RELAY_LINEAR_TIMESTAMP_WINDOW_SECONDS` (default: 60s)
5. Sanitize payload via `relay_core::sanitize`
6. Publish `EventEnvelope` to `webhooks.linear` Kafka topic

The source name `linear` appears in the envelope and can be used for routing in `[[serve.routes]]`.

---

## Required Environment Variable

```bash
HMAC_SECRET_LINEAR=<your-webhook-secret>
```

This is the secret you configure in Linear's webhook settings. Use a strong random value:

```bash
openssl rand -hex 32
```

If `HMAC_SECRET_LINEAR` is not set and `linear` is in `RELAY_ENABLED_SOURCES`, serve rejects all Linear webhooks with 401 (fail-closed).

---

## Webhook URL

```
POST /webhook/linear
```

Configure this in Linear Settings > API > Webhooks:

```
https://<your-host>/webhook/linear
```

---

## Linear Webhook Setup

1. Log in as a workspace owner
2. Go to **Settings > API > Webhooks**
3. Click **New webhook**
4. Set:
   - **URL**: `https://<your-host>/webhook/linear`
   - **Label**: a descriptive name (e.g. `hook-relay`)
   - **Secret**: value of `HMAC_SECRET_LINEAR`
   - **Events**: select Issue, Comment, and any others you need
5. Save

Linear webhook subscriptions are workspace-level — all events from all team members are delivered.

---

## Events

Configure in Linear Settings > API > Webhooks:

| Event Type | Triggers |
|---|---|
| `Issue` | Created, updated, removed |
| `Comment` | Created, updated, removed |
| `Project` | Created, updated |
| `Label` | Created, updated |

Linear delivers all subscribed event types to a single webhook URL. The `type` and `action` fields in the payload identify the specific event.

---

## Signature Format

Linear sends `Linear-Signature: <hex>` — a raw hex-encoded HMAC-SHA256 digest with no prefix.

This differs from GitHub's `sha256=` prefix. `hook serve` handles this correctly using the Linear-specific source handler.

---

## Timestamp Window

Linear includes a `webhookTimestamp` field in the payload (milliseconds since epoch). Serve validates this by default:

```bash
RELAY_ENFORCE_LINEAR_TIMESTAMP_WINDOW=true   # default
RELAY_LINEAR_TIMESTAMP_WINDOW_SECONDS=60     # default: 60s
```

Requests delivered more than 60 seconds after their claimed timestamp are rejected with 401. This prevents replay attacks.

Do not disable `RELAY_ENFORCE_LINEAR_TIMESTAMP_WINDOW` in production.

---

## Feedback Loop Prevention

When the agent updates issues or posts comments via the Linear API, Linear fires a webhook for those actions. To prevent the agent from responding to its own events:

1. Create a dedicated Linear service account for the agent (e.g. `agent-bot@yourteam.com`)
2. Note its Linear user ID (`LINEAR_AGENT_USER_ID`)
3. In smash adapter logic or OpenClaw transforms, skip events where `data.userId == LINEAR_AGENT_USER_ID`

Unlike GitHub, Linear has no automatic `[bot]` suffix — actor filtering must be done by user ID.

```typescript
// In OpenClaw linear.ts transform
if (payload.data.userId === process.env.LINEAR_AGENT_USER_ID) return null;
```

---

## Agent Identity Setup

1. Create a Linear account for the agent (use a service email)
2. Workspace owner invites the agent user
3. Owner adds the agent user to the relevant team(s)
4. Log in as the agent user → **Settings > API > Personal API keys** → Create key
5. Store the key as `LINEAR_AGENT_API_KEY` (used by OpenClaw to post comments/updates)
6. Store the user's Linear UUID as `LINEAR_AGENT_USER_ID` (used for feedback loop prevention)

The agent user should have **Member** role — enough to read issues and post comments.

---

## Local Development

Linear webhooks require a publicly reachable URL. Use Tailscale Funnel or a tunnel service to expose `hook serve` during development:

```bash
# Start hook serve locally
hook serve --app default-openclaw

# Expose via Tailscale Funnel
tailscale funnel --bg 8080

# Configure Linear webhook URL to your Funnel URL
# https://your-machine.tail-net.ts.net/webhook/linear
```

Then trigger test events by creating or updating issues in Linear.
