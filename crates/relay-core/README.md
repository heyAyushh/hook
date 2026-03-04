# relay-core

Shared Rust library for contracts, validation, envelope model, and security primitives.

## Modules

- `contract.rs`: app contract schema (`serve`, `smash`, profiles, transports, policies).
- `contract_validator.rs`: active-profile validation; fail-closed on security-critical issues; unsupported drivers rejected only when active.
- `model.rs`: `EventEnvelope`, `EventMeta`, `DlqEnvelope`, source/topic helpers.
- `signatures.rs`: constant-time signature/token verification.
- `sanitize.rs`: zero-trust payload sanitization and flags.
- `timestamps.rs`: timestamp-window validation for replay protection.
- `keys.rs`: dedup and cooldown key helpers.
- `kafka_config.rs`: shared Kafka core config loader.

## Design Constraints

- Backward-compatible envelope serialization.
- Strict validation by default (`validation_mode = strict`).
- Security checks fail closed.

## Build and Test

```bash
cargo test -p relay-core
```

## Related

- `docs/spec.md`
- `apps/default-openclaw/contract.toml`
- `src/main.rs`
- `crates/hook-runtime/src/smash/`
