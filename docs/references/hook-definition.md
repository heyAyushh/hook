# Hook CLI and Contract Reference

## The `hook` CLI

The `hook` binary is the unified entry point for all runtime roles.

```
hook <command> [flags]
```

### Commands

| Command | Description |
|---|---|
| `hook serve --app <id>` | Start webhook ingress server |
| `hook relay --topics <t1,t2> --output-topic <topic>` | Start Kafka fan-in relay |
| `hook smash --app <id>` | Start egress delivery consumer |
| `hook validate --app <id>` | Validate a contract without starting |

### `hook serve`

```bash
hook serve --app default-openclaw
hook serve --app default-openclaw --validation-mode debug
hook serve --app default-openclaw --contract /etc/relay/contract.toml
```

| Flag | Default | Description |
|---|---|---|
| `--app` | required | App ID to activate (selects profile from contract) |
| `--contract` | auto-discovered | Path to `contract.toml` (see discovery order below) |
| `--validation-mode` | `strict` | `strict` or `debug` (security-critical checks always enforced) |

### `hook relay`

```bash
hook relay --topics webhooks.github,webhooks.linear --output-topic webhooks.core
hook relay --topics webhooks.github --output-topic webhooks.core --group my-relay
```

| Flag | Default | Description |
|---|---|---|
| `--topics` | required | Comma-separated source topics to consume |
| `--output-topic` | required | Topic to forward messages to |
| `--group` | `hook-relay` | Kafka consumer group ID |

### `hook smash`

```bash
hook smash --app default-openclaw
hook smash --app default-openclaw --contract /etc/relay/contract.toml
```

| Flag | Default | Description |
|---|---|---|
| `--app` | required | App ID to activate |
| `--contract` | auto-discovered | Path to `contract.toml` |

### `hook validate`

Validates a contract for a given app ID without starting any server or consumer. Exits 0 if valid, non-zero on error.

```bash
hook validate --app default-openclaw
hook validate --app default-openclaw --validation-mode debug
```

---

## Contract File (`contract.toml`)

The contract is the single source of configuration for an app. It describes ingress adapters, egress adapters, routes, profiles, and transports.

### Discovery Order

1. `--contract <path>` CLI flag
2. `RELAY_CONTRACT_PATH` environment variable
3. `apps/<app-id>/contract.toml` (relative to repo root)
4. `contract.toml` in the current directory

### Top-Level Sections

```toml
[app]          # identity
[policies]     # validation behavior
[serve]        # ingress adapters and routes
[smash]        # egress adapters and routes
[profiles.*]   # named activation sets
[transports.*] # transport drivers (e.g. MCP)
```

### `[app]`

```toml
[app]
id = "default-openclaw"
name = "Default OpenClaw"
version = "1.0.0"
description = "Optional description"
```

| Key | Required | Description |
|---|---|---|
| `id` | yes | Machine-readable app identifier |
| `name` | no | Human-readable display name |
| `version` | no | Semver string |
| `description` | no | Description string |

### `[policies]`

```toml
[policies]
allow_no_output = false
validation_mode = "strict"
```

| Key | Default | Description |
|---|---|---|
| `allow_no_output` | `false` | If `true`, a profile with no smash output is allowed (requires `no_output_sink` set) |
| `validation_mode` | `"strict"` | `"strict"` or `"debug"` — debug relaxes non-security checks only |

### `[[serve.ingress_adapters]]`

Each adapter must declare `driver`. Available drivers:

#### `http_webhook_ingress`

```toml
[[serve.ingress_adapters]]
id = "http-ingress"
driver = "http_webhook_ingress"
bind = "0.0.0.0:8080"
path_template = "/webhook/{source}"
plugins = []   # optional
```

| Key | Required | Description |
|---|---|---|
| `id` | yes | Unique adapter identifier |
| `bind` | yes | Socket address to bind (e.g. `0.0.0.0:8080`) |
| `path_template` | yes | URL path template with `{source}` placeholder |
| `plugins` | no | List of plugin objects (run in order) |

#### `websocket_ingress`

```toml
[[serve.ingress_adapters]]
id = "ws-ingress"
driver = "websocket_ingress"
path_template = "/ws/{source}"
auth_mode = "bearer"
token_env = "WS_INGRESS_TOKEN"   # required when auth_mode = "bearer"
plugins = []
```

#### `mcp_ingest_exposed`

```toml
[[serve.ingress_adapters]]
id = "mcp-ingress"
driver = "mcp_ingest_exposed"
tool_name = "submit_event"
transport_driver = "streamable_http"
bind = "0.0.0.0:8090"
path = "/mcp"
auth_mode = "bearer"
token_env = "MCP_INGRESS_TOKEN"
max_payload_bytes = 65536
plugins = []
```

#### `kafka_ingress`

```toml
[[serve.ingress_adapters]]
id = "kafka-in"
driver = "kafka_ingress"
topics = ["external.events"]
group_id = "hook-serve-kafka"
brokers = "127.0.0.1:9092"   # optional, overrides KAFKA_BROKERS
plugins = []
```

### `[[serve.routes]]`

Routes define how serve dispatches events to Kafka topics.

```toml
[[serve.routes]]
id = "all-to-core"
source_match = "*"
event_type_pattern = "*"
target_topic = "webhooks.core"
```

| Key | Required | Description |
|---|---|---|
| `id` | yes | Unique route identifier |
| `source_match` | yes | Source glob (`github`, `linear`, `*`) |
| `event_type_pattern` | yes | Event type glob (`push`, `Issue.*`, `*`) |
| `target_topic` | yes | Kafka topic to publish matching events to |

### `[[smash.egress_adapters]]`

#### `openclaw_http_output`

```toml
[[smash.egress_adapters]]
id = "openclaw-output"
driver = "openclaw_http_output"
url = "http://127.0.0.1:18789/hooks/agent"
token_env = "OPENCLAW_WEBHOOK_TOKEN"
timeout_seconds = 20
max_retries = 5
plugins = []
```

| Key | Required | Description |
|---|---|---|
| `id` | yes | Unique adapter identifier |
| `url` | yes | OpenClaw hooks endpoint |
| `token_env` | yes | Env var name holding the bearer token |
| `timeout_seconds` | no (default 30) | HTTP request timeout |
| `max_retries` | no (default 3) | Max delivery retries before DLQ |
| `plugins` | no | List of plugin objects |

#### `kafka_output`

```toml
[[smash.egress_adapters]]
id = "kafka-out"
driver = "kafka_output"
topic = "processed.events"
brokers = "127.0.0.1:9092"   # optional, overrides KAFKA_BROKERS
plugins = []
```

#### `websocket_client_output` / `websocket_server_output`

```toml
[[smash.egress_adapters]]
id = "ws-client"
driver = "websocket_client_output"
url = "ws://127.0.0.1:9100/stream"
token_env = "WS_CLIENT_TOKEN"
reconnect_delay_seconds = 5

[[smash.egress_adapters]]
id = "ws-server"
driver = "websocket_server_output"
bind = "0.0.0.0:9200"
auth_mode = "bearer"
token_env = "WS_SERVER_TOKEN"
```

#### `mcp_tool_output`

```toml
[[smash.egress_adapters]]
id = "mcp-tool-out"
driver = "mcp_tool_output"
tool_name = "process_event"
transport = "ws-transport"     # references [transports.*] section
token_env = "MCP_TOOL_TOKEN"
timeout_seconds = 30
max_retries = 3
```

### `[[smash.routes]]`

```toml
[[smash.routes]]
id = "core-to-openclaw"
source_topic_pattern = "webhooks.core"
destinations = [
  { adapter_id = "openclaw-output", required = true }
]
```

| Key | Required | Description |
|---|---|---|
| `id` | yes | Unique route identifier |
| `source_topic_pattern` | yes | Kafka topic glob to match |
| `destinations` | yes | Array of `{ adapter_id, required }` |

`required = true` means a delivery failure causes DLQ routing. `required = false` makes delivery best-effort.

### `[profiles.*]`

Profiles define which adapters and routes are active when a given app ID is specified.

```toml
[profiles.default-openclaw]
label = "Default OpenClaw"
serve_adapters = ["http-ingress"]
smash_adapters = ["openclaw-output"]
serve_routes = ["all-to-core"]
smash_routes = ["core-to-openclaw"]
```

| Key | Required | Description |
|---|---|---|
| `label` | no | Human-readable profile name |
| `serve_adapters` | yes | Adapter IDs from `[[serve.ingress_adapters]]` |
| `smash_adapters` | yes | Adapter IDs from `[[smash.egress_adapters]]` |
| `serve_routes` | yes | Route IDs from `[[serve.routes]]` |
| `smash_routes` | yes | Route IDs from `[[smash.routes]]` |

### `[transports.*]`

Transport drivers used by adapters (e.g. for MCP):

```toml
[transports.ws-transport]
driver = "websocket_client"
url = "ws://127.0.0.1:9100"
token_env = "WS_TRANSPORT_TOKEN"
```

---

## Plugins

Plugins are declared inline on adapters and run in declaration order. All three drivers are available on both serve ingress adapters and smash egress adapters.

```toml
plugins = [
  { driver = "require_payload_field", pointer = "/repository/id" },
  { driver = "event_type_alias", from = "push", to = "git.push" },
  { driver = "add_meta_flag", flag = "has-repo" },
]
```

See [../plugins.md](../plugins.md) for full plugin reference.

---

## Minimal Working Example

```toml
[app]
id = "my-app"
name = "My App"

[policies]
allow_no_output = false

[[serve.ingress_adapters]]
id = "http-ingress"
driver = "http_webhook_ingress"
bind = "0.0.0.0:8080"
path_template = "/webhook/{source}"

[[serve.routes]]
id = "all-to-core"
source_match = "*"
event_type_pattern = "*"
target_topic = "webhooks.core"

[[smash.egress_adapters]]
id = "openclaw-output"
driver = "openclaw_http_output"
url = "http://127.0.0.1:18789/hooks/agent"
token_env = "OPENCLAW_WEBHOOK_TOKEN"
timeout_seconds = 20
max_retries = 5

[[smash.routes]]
id = "core-to-openclaw"
source_topic_pattern = "webhooks.core"
destinations = [{ adapter_id = "openclaw-output", required = true }]

[profiles.my-app]
serve_adapters = ["http-ingress"]
smash_adapters = ["openclaw-output"]
serve_routes = ["all-to-core"]
smash_routes = ["core-to-openclaw"]
```

Run with:

```bash
hook serve --app my-app &
hook relay --topics webhooks.github,webhooks.linear --output-topic webhooks.core &
hook smash --app my-app
```
