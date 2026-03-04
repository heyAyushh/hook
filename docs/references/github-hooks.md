# GitHub Webhook Source

## How It Works

`hook serve` accepts GitHub webhook deliveries at `/webhook/github`. Each request is validated before the payload is processed:

1. Read `HMAC_SECRET_GITHUB` from env — reject at startup if missing
2. Compute HMAC-SHA256 over the raw request body
3. Compare to `X-Hub-Signature-256: sha256=<hex>` header using constant-time comparison
4. Extract `X-GitHub-Event` and `X-GitHub-Delivery` headers for envelope metadata
5. Sanitize payload via `relay_core::sanitize`
6. Publish `EventEnvelope` to `webhooks.github` Kafka topic

The source name `github` appears in the envelope and can be used for routing in `[[serve.routes]]`.

---

## Required Environment Variable

```bash
HMAC_SECRET_GITHUB=<your-webhook-secret>
```

This is the secret you configure in GitHub's webhook settings. Use a strong random value (32+ bytes):

```bash
openssl rand -hex 32
```

If `HMAC_SECRET_GITHUB` is not set and `github` is in `RELAY_ENABLED_SOURCES`, serve rejects the request with 401 (fail-closed).

---

## Webhook URL

```
POST /webhook/github
```

Configure this URL in GitHub's webhook settings:

```
https://<your-host>/webhook/github
```

Content type must be `application/json`.

---

## GitHub App Setup

A GitHub App provides:
- Webhook delivery to your relay URL
- Bot identity for the agent (`app-name[bot]`)
- Fine-grained permissions for outbound API calls
- Short-lived installation access tokens (1 hour)

### Create via gh CLI (Manifest Flow)

```bash
APP_NAME="openclaw-agent"
RELAY_BASE_URL="https://your-host.example.com"
WEBHOOK_URL="${RELAY_BASE_URL}/webhook/github"
WEBHOOK_SECRET="${HMAC_SECRET_GITHUB}"

# Build manifest
cat > /tmp/app-manifest.json <<JSON
{
  "name": "${APP_NAME}",
  "url": "${RELAY_BASE_URL}",
  "public": false,
  "webhook_secret": "${WEBHOOK_SECRET}",
  "hook_attributes": {"url": "${WEBHOOK_URL}", "active": true},
  "default_permissions": {
    "pull_requests": "write",
    "contents": "read",
    "metadata": "read"
  },
  "default_events": [
    "pull_request",
    "pull_request_review",
    "pull_request_review_comment",
    "pull_request_review_thread",
    "issue_comment"
  ]
}
JSON

# Open manifest registration URL
STATE="$(openssl rand -hex 16)"
ENCODED="$(jq -Rs @uri < /tmp/app-manifest.json)"
MANIFEST_URL="https://github.com/settings/apps/new?state=${STATE}&manifest=${ENCODED}"
echo "$MANIFEST_URL"
# macOS: open "$MANIFEST_URL"

# After browser flow, copy the ?code= value and convert
CODE="paste_code_here"
gh api --method POST "/app-manifests/${CODE}/conversions" > /tmp/app-created.json
jq '{id, client_id}' /tmp/app-created.json
```

For an org app, replace `https://github.com/settings/apps/new` with `https://github.com/organizations/<org>/settings/apps/new`.

### Create via Web UI

1. Go to **Settings > Developer settings > GitHub Apps > New GitHub App**
2. Set:
   - **Webhook URL**: `https://<your-host>/webhook/github`
   - **Webhook secret**: value of `HMAC_SECRET_GITHUB`
   - **Permissions**: Pull requests (read/write), Contents (read), Metadata (read)
   - **Events**: `pull_request`, `pull_request_review`, `pull_request_review_comment`, `issue_comment`
3. Generate and download a private key
4. Note the App ID and Installation ID

### Install the App

- **Personal account**: Settings > Applications > Install > select repos
- **Organization**: Org Settings > Installed GitHub Apps > Install > select repos

---

## Events to Subscribe

| Event | Purpose |
|---|---|
| `pull_request` | PR opened, closed, synchronized, labeled |
| `pull_request_review` | Review submitted, dismissed |
| `pull_request_review_comment` | Inline review comments |
| `pull_request_review_thread` | Thread resolved/unresolved |
| `issue_comment` | PR conversation comments |

These events generate `EventEnvelope` entries with `source = "github"` and `event_type` matching the GitHub event name.

---

## Feedback Loop Prevention

When the agent posts reviews or comments via the GitHub App, GitHub fires a webhook for that action. To prevent the agent from responding to its own events, filter by sender:

GitHub App bot actions set `sender.login` to `app-name[bot]`. In smash adapter plugins or OpenClaw transforms:

```toml
# Example: require no bot sender (reject if sender ends with [bot])
# This is enforced in application logic, not a built-in plugin
```

In OpenClaw transforms:

```typescript
if (payload.sender.login.endsWith('[bot]')) return null;
```

The `[bot]` suffix is automatic — GitHub enforces it for all App bot actions.

---

## Agent Authentication (Outbound API Calls)

After receiving a webhook, the agent needs to authenticate GitHub API calls (posting reviews). Use installation tokens, not a static PAT:

```bash
# 1. Create JWT from App private key (expires 10 min)
# Use a library or openssl + base64 for JWT construction

# 2. Exchange for installation access token
TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$GITHUB_INSTALLATION_ID/access_tokens" \
  | jq -r .token)

# 3. Use token for API calls
curl -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/owner/repo/pulls/1/reviews"
```

Required env vars for outbound API calls:
- `GITHUB_APP_ID` — numeric app ID from app settings
- `GITHUB_APP_PRIVATE_KEY` — path to the downloaded `.pem` file
- `GITHUB_INSTALLATION_ID` — installation ID (also delivered per-event in `payload.installation.id`)

---

## Local Development

Use `gh webhook forward` to tunnel GitHub App events to a local serve instance:

```bash
# Start hook serve locally
hook serve --app default-openclaw

# In another terminal, forward GitHub App events
gh webhook forward \
  --events=pull_request,pull_request_review,issue_comment \
  --url=http://localhost:8080/webhook/github
```

This forwards events from your GitHub App installation to the local server without needing a public URL.

---

## Per-Repo Webhook (Alternative)

If a GitHub App is not available, configure per-repo webhooks:

1. Repo Settings > Webhooks > Add webhook
2. **Payload URL**: `https://<your-host>/webhook/github`
3. **Content type**: `application/json`
4. **Secret**: value of `HMAC_SECRET_GITHUB`
5. Select events (same list as above)

The `hook serve` endpoint is identical — only the GitHub-side delivery mechanism differs.
