# spec.md
Version: `1.1.0`
Status: `Living` (core implemented; some profile variants remain planned)
Date: `2026-03-04`
Repository: `hook-serve`

## 1. Purpose
This spec defines the exact architecture, contracts, validation rules, and runtime behavior for a configurable event platform inside this repository.

The platform has three runtime roles:
1. `serve`: ingestion consumer — receives events from external sources via configured ingress adapters (HTTP webhook, WebSocket, MCP push, external Kafka).
2. `relay`: mandatory internal Kafka-to-Kafka bridge — consumes from serve-side source topics and republishes to the internal core topic.
3. `smash`: delivery producer — routes events to external destinations via configured egress adapters (HTTP POST, WebSocket, MCP tool call, external Kafka).

Serve ingress adapters and smash egress adapters are symmetric pairs:

| Ingress adapter (serve) | Egress adapter (smash) |
|---|---|
| HTTP webhook receive | HTTP POST delivery |
| WebSocket frame receive | WebSocket frame send |
| MCP push (exposed tool endpoint) | MCP tool call |
| External Kafka consume | External Kafka produce |

Multiple serve and smash adapters can be active simultaneously in any combination: 1:1, 1:n, n:1, or n:m. Each `kafka_ingress` and `kafka_output` adapter is independently configurable — brokers, topics, and security settings are per-adapter and can target the relay's internal Kafka or any external Kafka cluster on any topic.

`serve` and `smash` are contract-driven: behavior is fully defined in `apps/<app>/contract.toml` and activated by a named profile. `relay` is runtime-only: it has no contract section and is configured entirely via CLI flags and env vars.

The relay's internal Kafka is the mandatory backbone between `serve` and `smash` in every profile.

## 2. Goals
1. Keep default behavior as `HTTP webhook -> Kafka -> OpenClaw hook`.
2. Make ingress and egress pluggable via app-owned contracts.
3. Keep MCP optional and plug-and-play.
4. Keep WebSocket optional and plug-and-play.
5. Enforce strict fail-closed validation by default.
6. Preserve backward compatibility for existing workflows.

## 3. Non-Goals
1. No direct `serve` to destination bypass that skips Kafka.
2. No smash-to-serve loop flow in this version.
3. No requirement that MCP must exist.
4. No runtime where `serve` has egress adapters.
5. No runtime where `smash` has ingress adapters.

## 4. Canonical Topology
1. External event arrives at a `serve` ingress adapter (HTTP, WebSocket, MCP push, or external Kafka consume).
2. `serve` normalizes, validates, sanitizes, and creates an `EventEnvelope`.
3. `serve` publishes the `EventEnvelope` to an internal serve-side source topic.
4. `relay` consumes from source topics and republishes to the internal core Kafka topic.
5. `smash` consumes from the core Kafka topic.
6. `smash` resolves the active smash route and dispatches to one or more egress adapters.
7. Each egress adapter delivers or produces to its configured external destination (HTTP, WebSocket, MCP tool call, or external Kafka produce).

## 5. Repository Structure
1. Service runtime remains under `src/` for `hook-serve`.
2. CLI/orchestration binary lives under `tools/hook/`.
3. Reusable shared code remains under `crates/`.
4. App contracts live in `apps/<app>/contract.toml`.
5. Global Kafka core config lives in `config/kafka-core.toml`.

## 6. Core Definitions

### 6.1 EventEnvelope
Required fields:
1. `id: string` (uuid v4)
2. `source: string` (normalized lowercase)
3. `event_type: string`
4. `received_at: string` (RFC3339 UTC)
5. `payload: object`

Optional field:
1. `meta: object`

`meta` allowed keys:
1. `trace_id: string`
2. `ingress_adapter: string`
3. `route_key: string`
4. `flags: array<string>`

Compatibility requirement:
1. Existing consumers must function with old fields only.
2. New optional fields must never break deserialization.

### 6.2 DeliveryResult
`DeliveryResult` states:
1. `success`
2. `retryable_failure`
3. `permanent_failure`

## 7. Config Model

### 7.1 Global Kafka core config (`config/kafka-core.toml`)
Required keys:
1. `[kafka_core] brokers`
2. `[kafka_core] security_protocol`
3. `[kafka_core] topic_prefix_core`
4. `[kafka_core] dlq_topic`
5. `[kafka_core.producer_defaults]` table
6. `[kafka_core.consumer_defaults]` table

Optional keys:
1. `[kafka_core] auto_create_topics`
2. `[kafka_core] topic_partitions`
3. `[kafka_core] topic_replication_factor`
4. `[kafka_core] allow_plaintext`
5. `[kafka_core.tls]` table
6. `[kafka_core.sasl]` table

Example:
```toml
[kafka_core]
brokers = ["100.64.0.10:9093"]
security_protocol = "ssl"
allow_plaintext = false
topic_prefix_core = "webhooks"
dlq_topic = "webhooks.dlq"
auto_create_topics = true
topic_partitions = 3
topic_replication_factor = 1

[kafka_core.producer_defaults]
publish_queue_capacity = 4096
publish_max_retries = 5
publish_backoff_base_ms = 200
publish_backoff_max_ms = 5000

[kafka_core.consumer_defaults]
commit_mode = "async"
auto_offset_reset = "latest"

[kafka_core.tls]
cert_path = "/etc/relay/certs/relay.crt"
key_path = "/etc/relay/certs/relay.key"
ca_path = "/etc/relay/certs/ca.crt"
```

### 7.2 App contract (`apps/<app>/contract.toml`)
Required sections:

```
[app]
[policies]
[serve]
[[serve.ingress_adapters]]
[[serve.routes]]
[smash]
[[smash.egress_adapters]]
[[smash.routes]]
[profiles.<name>]
```

Optional sections:

```
[mcp]
[websocket]
[transports.<name>]
```

Unknown top-level or adapter keys are validation errors.
Unknown enum values are validation errors.
Each adapter may include an optional `plugins` array.

#### 7.2.1 `[app]` keys
Required:
- `id: string` — unique app identifier (kebab-case)
- `name: string` — human-readable display name
- `version: string` — semver string

Optional:
- `description: string`

Example:
```toml
[app]
id = "my-webhook-app"
name = "My Webhook App"
version = "1.0.0"
description = "Receives GitHub/Linear webhooks and delivers to OpenClaw."
```

#### 7.2.2 `[policies]` keys
Optional:
- `allow_no_output: bool` (default `false`) — when `true`, a profile with zero enabled smash outputs does not fail validation; `no_output_sink` must also be set
- `no_output_sink: string` — required when `allow_no_output = true`; defines the fate of consumed events with no egress: `"discard"` (offset committed, event silently dropped) or `"dlq"` (event forwarded to the configured DLQ topic before commit)
- `validation_mode: string` — `"strict"` (default) or `"debug"`

Example:
```toml
[policies]
allow_no_output = false
validation_mode = "strict"
```

#### 7.2.3 `[profiles.<name>]` keys
Required:
- `label: string` — human-readable name for this profile

Optional:
- `serve_adapters: array<string>` — adapter IDs from `[[serve.ingress_adapters]]` to enable; if omitted, no serve adapters are active for this profile
- `smash_adapters: array<string>` — adapter IDs from `[[smash.egress_adapters]]` to enable; if omitted, no smash adapters are active for this profile
- `serve_routes: array<string>` — route IDs from `[[serve.routes]]` to enable; if omitted, no serve routes are active
- `smash_routes: array<string>` — route IDs from `[[smash.routes]]` to enable; if omitted, no smash routes are active
- `env: table` — profile-level env var overrides (key-value strings)

Omitting any adapter or route list is not an implicit "enable all" — it means nothing in that category is active. Profiles must explicitly enumerate every adapter and route they activate.

Example:
```toml
[profiles.default-openclaw]
label = "Default OpenClaw"
serve_adapters = ["http-ingress"]
smash_adapters = ["openclaw-output"]
serve_routes = ["all-to-core"]
smash_routes = ["core-to-openclaw"]
```

#### 7.2.4 `[transports.<name>]` keys
Defines named outbound transport configurations used by MCP **client** adapters (`mcp_tool_output`) via `transport_ref`. This section is for adapters that call an external MCP server. It is not used by `mcp_ingest_exposed`, which hosts its own endpoint.

Required:
- `driver: string` — `"stdio_jsonrpc"` or `"http_sse"`

Driver-specific keys for `http_sse`:
- `url: string` — remote MCP server URL
- `auth_mode: string`

Example:
```toml
[transports.my-mcp]
driver = "http_sse"
url = "https://mcp.example.com/sse"
auth_mode = "bearer"
```

## 8. Adapter Catalog

### 8.1 Serve ingress adapter drivers
- `http_webhook_ingress`
- `websocket_ingress`
- `mcp_ingest_exposed`
- `kafka_ingress`

### 8.2 Smash egress adapter drivers
- `openclaw_http_output`
- `mcp_tool_output`
- `websocket_client_output`
- `websocket_server_output`
- `kafka_output`

## 9. Adapter Contracts

### 9.1 `http_webhook_ingress`
Required config:
- `bind`
- `path_template` (default `/webhook/{source}`)

Behavior:
- Receives POST JSON payload.
- Uses source handlers for auth and event extraction.

### 9.2 `websocket_ingress`
Required config:
- `path_template` (default `/ingest/ws/{source}`)
- `auth_mode`

Behavior:
- Accepts authenticated text frames containing JSON object payload.
- Each valid frame becomes one inbound event.

### 9.3 `mcp_ingest_exposed`
This adapter operates in **server mode**: it hosts an MCP tool endpoint that external MCP clients call to inject events into `serve`. It does not call any external MCP server and does not use `transport_ref`.

Required config:
- `tool_name` (default `serve_ingest_event`)
- `transport_driver: string` — must be `"http_sse"` for exposed ingress
- `bind: string` — address to listen on (e.g. `"0.0.0.0:4000"`)
- `auth_mode: string` — auth strategy for inbound MCP clients
- `max_payload_bytes`

Tool request schema:
- `source: string` required
- `payload: object` required
- `event_type: string` optional
- `headers: object` optional
- `metadata: object` optional

Tool response schema:
- `status: string`
- `event_id: string`
- `source: string`
- `event_type: string`
- `kafka_topic: string`
- `queued_at: string`

### 9.4 `kafka_ingress`
Required config:
- `topics: array<string>`
- `group_id: string`

Behavior:
- Consumes external Kafka topics.
- Converts messages to `EventEnvelope` via configured mapping.

### 9.5 `openclaw_http_output`
Required config:
- `url`
- `token_env`
- `timeout_seconds`
- `max_retries`

Behavior:
- Sends mapped event payload to OpenClaw hook endpoint.
- Retry policy follows adapter settings.

### 9.6 `mcp_tool_output`
Required config:
- `tool_name`
- `transport_ref` — references a named entry in `[transports.<name>]`

Supported transport drivers (defined in `[transports.<name>]`):
- `stdio_jsonrpc`
- `http_sse`

Behavior:
- Calls MCP tool once per routed event.
- Uses `EventEnvelope` payload plus route metadata.

### 9.7 `websocket_client_output`
Required config:
- `url`
- `auth_mode`
- `send_timeout_ms`
- `retry_policy`

### 9.8 `websocket_server_output`
Required config:
- `bind`
- `path`
- `auth_mode`
- `max_clients`
- `queue_depth_per_client`
- `send_timeout_ms`

### 9.9 `kafka_output`
Required config:
- `topic`
- `key_mode`

Behavior:
- Republishes `EventEnvelope` to configured Kafka topic.

### 9.10 Adapter Plugins (Serve + Smash)
Optional adapter key:
- `plugins: array<object>`

Supported plugin drivers:
- `event_type_alias`
- `require_payload_field`
- `add_meta_flag`

Execution rules:
1. Plugins execute in declaration order.
2. `require_payload_field` fails closed when the JSON pointer is missing.
3. `add_meta_flag` appends deduplicated entries to `EventEnvelope.meta.flags`.
4. Plugin configuration is validated for active adapters in the selected profile.

## 10. Routing

### 10.1 Serve routes
Each serve route defines:
- `id: string` — unique identifier referenced by `[profiles.<name>] serve_routes`
- `source_match: string` — source name or glob pattern
- `event_type_pattern: string` — event type match pattern
- `target_topic: string` — internal serve-side source topic to publish to (consumed by relay)

At least one serve route must exist for an active profile.

### 10.2 Smash routes
Each smash route defines:
- `id: string` — unique identifier referenced by `[profiles.<name>] smash_routes`
- `source_topic_pattern: string` — Kafka core topic pattern to consume from
- `event_filters: array<string>` (optional) — additional filter expressions
- `destinations: array<RouteDestination>` — one or more egress targets

`RouteDestination` fields:
- `adapter_id: string` — references an adapter in `[[smash.egress_adapters]]`
- `required: bool` (default `true`) — when `true`, commit is blocked until delivery succeeds; when `false`, failure never blocks commit

At least one smash route must exist for an active profile.

## 11. Mandatory Invariants
1. Every active event path must publish from `serve` into an internal serve-side source topic.
2. `relay` must be running, consuming from all active serve-side source topics, and republishing to the internal core Kafka topic.
3. Every active event path must consume from the internal core Kafka topic into `smash`.
4. `serve` contract cannot reference any egress adapter.
5. `smash` contract cannot reference any ingress adapter.
6. Direct serve-to-destination config is invalid.
7. A profile with zero enabled smash outputs is invalid unless `[policies] allow_no_output = true` and `no_output_sink` is also set.
8. Security-critical required keys missing is always fatal.

## 12. Validation Modes

### 12.1 Strict mode (default)
Any required validation failure blocks startup.
Security-critical checks are mandatory.

### 12.2 Debug mode
Non-security checks may be relaxed.
Security-critical checks are never relaxed.
Runtime must log explicit debug-relaxation status.
Health/status output must include validation mode.

Validation mode is set via `[policies] validation_mode = "strict" | "debug"` in the app contract, or overridden at runtime via the `--validation-mode` CLI flag.

Security-critical classes:
- auth prerequisite checks
- schema and payload integrity checks
- sanitizer configuration integrity
- Kafka core invariants
- required adapter schema integrity

## 13. Serve Processing Pipeline
For each inbound event:
1. ingest adapter receives raw input
2. source normalization
3. source-specific auth and signature checks
4. payload parse and schema checks
5. `event_type` extraction
6. dedup and cooldown checks
7. sanitizer execution
8. serve plugin execution (if configured on the active ingress adapter)
9. `EventEnvelope` creation
10. publish to internal serve-side source topic
11. adapter-specific response

## 14. Smash Processing Pipeline
For each consumed envelope:
1. read from Kafka core topic
2. route match resolution
3. smash plugin execution per destination adapter (if configured)
4. required egress deliveries (destinations with `required = true`)
5. optional egress deliveries (destinations with `required = false`)
6. commit when all required egress succeed
7. retry on retryable failures
8. publish DLQ on exhausted failure

## 15. Failure Handling
- Retryable output failures follow per-adapter backoff.
- Permanent output failures skip retry and move to DLQ when configured.
- Commit does not occur before required outputs succeed.
- Optional output failures never block commit.

## 16. Observability

### 16.1 Logs
Minimum log fields:
- `trace_id`
- `event_id`
- `source`
- `event_type`
- `ingress_adapter`
- `egress_adapter`
- `kafka_topic`
- `delivery_state`

### 16.2 Metrics
Required metrics:
- `serve_ingress_events_total{adapter,source}`
- `serve_publish_success_total{topic}`
- `serve_publish_failure_total{topic,reason}`
- `smash_consume_events_total{topic}`
- `smash_egress_success_total{adapter}`
- `smash_egress_failure_total{adapter,reason}`
- `smash_commit_total{topic}`
- `smash_dlq_total{topic}`

### 16.3 Health endpoints
- `/health` basic liveness.
- `/ready` readiness including adapter and Kafka core state.
- `/ready` must expose `validation_mode` and active profile name.

## 17. CLI Spec
The `hook` binary lives under `tools/hook/`.

Primary runtime commands:
```
hook serve  [--app <id> | --contract <path>]
            [--profile <name>] [--validation-mode strict|debug]
            [--instance-id <id>]
hook smash  [--app <id> | --contract <path>]
            [--profile <name>] [--validation-mode strict|debug]
            [--instance-id <id>]
hook relay  [--topics <csv>] [--output-topic <topic>] [--group-id <id>]
            [--brokers <list>] [--mode envelope|raw]
            [--max-retries <n>] [--backoff-base-ms <ms>] [--backoff-max-ms <ms>]
```

Legacy serve/smash compatibility overrides (optional, applied after contract load):
```
hook serve [--bind <addr>] [--brokers <list>] [--enabled-sources <csv>]
           [--source-topic-prefix <prefix>]
hook smash [--topics <csv>] [--webhook-url <url>] [--webhook-token <token>]
           [--group-id <id>] [--brokers <list>]
```

Config and validation commands:
```
hook config validate
hook config show
hook config import [--toml <path>] [--env-file <path>]...
```

Diagnostics and tooling commands:
```
hook debug capabilities [--json]
hook debug env [--no-redact]
hook test env
hook test smoke serve|relay|smash
hook replay webhook --url <url> --file <path> [--source <src>] [--header <k:v>]...
hook replay kafka   --topic <topic> --file <path> [--brokers <list>]
hook introduce [--toml <path>] [--dry-run]
hook logs collect [--scope auto|full|runtime|system] [--format bundle|stream|both]
hook logs tail    [--scope auto|full|runtime|system] [--lines <n>] [--follow]
hook logs sources
hook infra firecracker run|network-up|network-down|build-rootfs
hook infra broker      list|show
hook infra systemd     status|logs|restart <unit>
hook infra certs       gen [--dir <path>] [--ca] [--relay] [--consumer]
```

Global flags (apply to all commands):
```
--profile <name>              Profile name (default: "default-openclaw")
--app <id>                    App ID; selects contract at apps/<id>/contract.toml
--contract <path>             Explicit contract TOML path (overrides --app)
--config <path>               Explicit hook profile TOML path
--env-file <path>             Load env file (repeatable)
--force                       Bypass non-security-critical failures
--json                        Machine-readable JSON output
--validation-mode strict|debug  Override contract validation mode
```

Contract discovery order (first match wins):
1. `--contract <path>` if provided.
2. `apps/<id>/contract.toml` relative to repo root if `--app <id>` is provided.
3. `contract.toml` in the current working directory.
4. Built-in compatibility contract for profile `default-openclaw` (embedded fallback for `serve` and `smash` only).

`relay` never loads a contract regardless of discovery. `serve` and `smash` always run with a resolved contract (explicit, discovered, or embedded fallback), so Kafka-core invariants are always enforced.

Behavior:
- Command fails non-zero on validation failure.
- `--force` cannot bypass security-critical failures.
- `--validation-mode debug` cannot bypass security-critical checks.

## 18. Default Profiles

### 18.1 `default-openclaw`
- Serve ingress adapters: `["http-ingress"]` (`http_webhook_ingress`).
- Smash egress adapters: `["openclaw-output"]` (`openclaw_http_output`).
- Serve routes: `["all-to-core"]`.
- Smash routes: `["core-to-openclaw"]`.
- MCP disabled.
- WebSocket disabled.

### 18.2 `default-openclaw-mcp-ingest`
- Same as `default-openclaw`.
- Adds serve ingress adapter `["mcp-ingest"]` (`mcp_ingest_exposed`).
- Keeps serve route `["all-to-core"]` and smash route `["core-to-openclaw"]`.

### 18.3 `default-openclaw-mcp-smash`
- Same as `default-openclaw`.
- Adds smash egress adapter `["mcp-output"]` (`mcp_tool_output`).
- Keeps serve route `["all-to-core"]` and smash route `["core-to-openclaw"]`.

### 18.4 `default-openclaw-ws-smash`
- Same as `default-openclaw`.
- Adds smash egress adapter `["ws-client-output"]` (`websocket_client_output`).
- Keeps serve route `["all-to-core"]` and smash route `["core-to-openclaw"]`.

All profiles still route through Kafka core.

## 19. Backward Compatibility
- Keep command semantics for existing `hook serve`, `hook smash`, and `hook relay` operators.
- Keep `kafka-openclaw-hook` as the binary name for the existing consumer app under `apps/kafka-openclaw-hook/`; it is the backend for the `default-openclaw` profile.
- Existing envelope consumers remain compatible.
- Existing env vars remain supported through the env mapping layer.

## 20. Security Requirements
1. Fail closed on missing auth material.
2. Never log raw unauthorized payloads.
3. Maintain sanitizer boundary behavior.
4. Require explicit plaintext Kafka opt-in (`allow_plaintext = true`).
5. Enforce origin/auth checks for WebSocket and MCP endpoints when enabled.

## 21. Testing Requirements

### 21.1 Contract validation tests
- invalid adapter type
- missing required fields
- serve egress declaration rejection
- smash ingress declaration rejection
- Kafka core invariant rejection
- `allow_no_output` policy enforcement

### 21.2 Runtime tests
- serve HTTP ingress parity
- serve MCP ingress parity
- serve WebSocket ingress parse/auth behavior
- serve plugin execution and fail-closed behavior
- smash OpenClaw output retry behavior
- smash MCP output invocation
- smash WebSocket output backpressure
- smash Kafka output republish behavior
- smash plugin execution and fail-closed behavior

### 21.3 Security tests
- strict mode fail-closed behavior
- debug mode non-security-only relaxation
- no bypass of security-critical validations
- `--force` cannot override security-critical failures
- `--validation-mode debug` cannot override security-critical failures

### 21.4 E2E tests
1. Default flow: `HTTP webhook → Kafka → OpenClaw` (`default-openclaw`).
2. MCP ingest profile flow (`default-openclaw-mcp-ingest`).
3. MCP smash profile flow (`default-openclaw-mcp-smash`).
4. WebSocket egress profile flow (`default-openclaw-ws-smash`).

## 22. Acceptance Criteria
1. All active profiles must be contract-valid before runtime starts.
2. Default profile behavior matches current architecture.
3. Optional adapters can be enabled without code changes.
4. MCP remains optional and independent on serve and smash.
5. Kafka remains central in all profiles.
6. Production startup fails on any security-critical validation error.

## 23. Rollout
1. Implement config and validation layer first.
2. Refactor serve ingress runtime second.
3. Refactor smash egress runtime third.
4. Add optional adapters fourth.
5. Keep compatibility wrapper and migrate docs/scripts last.
