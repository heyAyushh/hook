# kafka-openclaw-hook

Compatibility binary for smash runtime execution.

## Purpose

- Preserve the historical `kafka-openclaw-hook` process name and deployment unit.
- Delegate behavior to `crates/hook-runtime` so smash adapters remain reusable and plug-and-play.

## Runtime Path

1. `apps/kafka-openclaw-hook/src/main.rs` initializes logging.
2. It calls `hook_runtime::smash::run_from_env()`.
3. `hook-runtime` loads smash config from env.
4. `hook-runtime` consumes Kafka, matches smash routes, applies adapter plugins, and delivers via egress adapters.

## Supported Smash Egress Adapters

- `openclaw_http_output`
- `mcp_tool_output`
- `websocket_client_output`
- `websocket_server_output`
- `kafka_output`

## Smash Plugin Drivers

Per-adapter plugin list (`plugins = [...]`) supports:
- `event_type_alias`
- `require_payload_field`
- `add_meta_flag`

## Environment

Required at minimum:
- `KAFKA_BROKERS`

Additional required env depends on active adapter set.
For example, OpenClaw output needs:
- `OPENCLAW_WEBHOOK_URL`
- `OPENCLAW_WEBHOOK_TOKEN`

Useful options:
- `KAFKA_GROUP_ID` (default `kafka-openclaw-hook`)
- `KAFKA_TOPICS`
- `KAFKA_DLQ_TOPIC`
- `HOOK_ALLOW_NO_OUTPUT`
- `HOOK_NO_OUTPUT_SINK=discard|dlq`

## Build and Test

```bash
cargo run -p kafka-openclaw-hook
cargo test -p kafka-openclaw-hook
cargo test -p hook-runtime
```

## Related Docs

- `crates/hook-runtime/README.md`
- `tools/hook/README.md`
- `apps/default-openclaw/contract.toml`
