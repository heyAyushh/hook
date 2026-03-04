# Apps

Runtime app contracts and compatibility binaries.

## Directories

- `default-openclaw/`: canonical compatibility contract profile (`contract.toml`), default flow `http_webhook_ingress -> kafka core -> openclaw_http_output`.
- `kafka-openclaw-hook/`: compatibility binary wrapper that calls `hook_runtime::smash::run_from_env()` and preserves historical deployment entrypoint stability.

## Contract Ownership

Each app owns its contract at `apps/<app>/contract.toml`.

Contract sections:
- `[serve]` and `[[serve.ingress_adapters]]`
- `[smash]` and `[[smash.egress_adapters]]`
- `[profiles.<name>]` for activation

Only adapters/routes selected by the active profile are runtime-active.

## Related Docs

- `tools/hook/README.md`
- `crates/hook-runtime/README.md`
- `docs/spec.md`
