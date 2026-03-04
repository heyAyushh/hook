# Tailscale Deployment

Tailscale Funnel exposes `hook serve` to the public internet over HTTPS with automatic TLS. GitHub and Linear require a publicly reachable webhook URL — Funnel is the simplest way to provide one.

---

## Architecture Options

| Scenario | Tailscale Feature | External Access |
|---|---|---|
| **Recommended: colocated hook serve + OpenClaw** | **Funnel + localhost** | Ingress only |
| hook serve on one node, OpenClaw on another tailnet node | **Funnel + MagicDNS** | Ingress only |
| Private webhook delivery (self-hosted Git) | **MagicDNS only** | No (tailnet only) |

---

## Option A: Tailscale Funnel (Recommended)

Funnel proxies HTTPS traffic from the public internet to your local `hook serve` instance.

```bash
# Expose hook serve on port 8080 via Funnel
tailscale funnel --bg 8080

# Your public URL:
# https://your-machine.tail-net.ts.net/
```

Configure webhook URLs in GitHub and Linear:
- GitHub: `https://your-machine.tail-net.ts.net/webhook/github`
- Linear: `https://your-machine.tail-net.ts.net/webhook/linear`

**Funnel requirements:**
- Enable Funnel in Tailscale admin ACLs: `"nodeAttrs": [{"target": ["*"], "attr": ["funnel"]}]`
- HTTPS only — automatic via Tailscale
- External port 443 proxied to your local port

---

## Option B: Private-Only (Tailnet Internal)

When both `hook serve` and event sources are on the same tailnet (e.g. self-hosted Git):

```bash
# Bind hook serve to the tailscale interface
RELAY_BIND_ADDR="$(tailscale ip -4):8080"

hook serve --app default-openclaw
# Set RELAY_BIND_ADDR env var or use contract bind address
```

Other tailnet nodes reach it via MagicDNS:
```
https://hook-server.tail-net.ts.net:8080/webhook/github
```

---

## Option C: Funnel + MagicDNS (Distributed)

When `hook serve` and OpenClaw run on different tailnet nodes:

```
Internet                      Tailnet
─────────                     ───────────────────────────────
GitHub ──► Funnel ──► hook serve ──► OpenClaw
Linear ──►           (node-a.ts.net)   (node-b.ts.net:18789)
```

```bash
# On node-a: expose hook serve
tailscale funnel --bg 8080

# Set OpenClaw URL to MagicDNS address (OpenClaw node)
OPENCLAW_WEBHOOK_URL=http://node-b.tail-net.ts.net:18789/hooks/agent
```

No public exposure of OpenClaw. All hook→OpenClaw traffic is WireGuard-encrypted via tailnet.

---

## Systemd Service

```ini
# /etc/systemd/system/hook-serve.service
[Unit]
Description=hook serve (webhook ingress)
After=network-online.target tailscaled.service
Wants=network-online.target tailscaled.service

[Service]
Type=simple
User=hook
Group=hook
EnvironmentFile=/etc/relay/.env
ExecStart=/usr/local/bin/hook serve --app default-openclaw
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

For Funnel as a persistent service:

```ini
# /etc/systemd/system/tailscale-funnel.service
[Unit]
Description=Tailscale Funnel (hook serve ingress)
After=tailscaled.service
Wants=tailscaled.service

[Service]
Type=simple
ExecStart=tailscale funnel 8080
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable both:

```bash
systemctl daemon-reload
systemctl enable --now hook-serve tailscale-funnel
```

---

## Funnel Config File (JSON)

For persistent Funnel configuration (useful in containers or CI):

```json
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://127.0.0.1:8080"
        }
      }
    }
  },
  "AllowFunnel": {
    "${TS_CERT_DOMAIN}:443": true
  }
}
```

Pass to Tailscale sidecar via `TS_SERVE_CONFIG=/config/serve.json`.

---

## Verify Funnel

```bash
# Confirm Funnel is active
tailscale funnel status

# Test from an external machine
curl -I https://your-machine.tail-net.ts.net/webhook/github
# Expected: 405 Method Not Allowed (GET is rejected, POST is required)
# 405 confirms hook serve is receiving traffic
```

A `405` on GET is correct behavior — `hook serve` only accepts POST on webhook paths.

---

## Proxy Headers

When `hook serve` is behind Tailscale Funnel, the real client IP arrives via `X-Forwarded-For`. Enable proxy trust to use it for rate limiting:

```bash
RELAY_TRUST_PROXY_HEADERS=true
RELAY_TRUSTED_PROXY_CIDRS=100.64.0.0/10   # Tailscale CGNAT range
```

Only set `RELAY_TRUSTED_PROXY_CIDRS` to the actual proxy CIDR. An empty value with `RELAY_TRUST_PROXY_HEADERS=true` is a startup error.
