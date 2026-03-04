---
name: relay-core
description: >
  Maintain shared relay-core contracts, validation, envelope models, and
  security primitives used by serve, relay, smash, and hook-runtime.
  Use when changing contract schema, active-profile validation, model
  compatibility, or signature/sanitization/timestamp logic.
---

# relay-core Skill

## Scope

- `src/contract.rs`: app contract schema and driver enums
- `src/contract_validator.rs`: active-profile fail-closed validation
- `src/model.rs`: envelope and metadata contracts
- `src/signatures.rs`: auth/signature verification helpers
- `src/sanitize.rs`: payload sanitization and flags
- `src/timestamps.rs`: replay-window checks
- `src/keys.rs`: dedup/cooldown key helpers
- `src/kafka_config.rs`: shared Kafka core config model

## Guardrails

- keep serialized envelope compatibility stable
- reject unknown/invalid active adapter configs fail-closed
- allow inactive unknown drivers for profile portability
- avoid weakening signature/timestamp checks
- keep sanitizer behavior explicit and test-backed

## Change Workflow

1. Edit only the module owning the behavior.
2. Add or adjust focused unit tests.
3. Update docs/spec/changelog for contract changes.
4. Run:
- `cargo fmt --all`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test -p relay-core`

## References

- `crates/relay-core/README.md`
- `docs/spec.md`
- `apps/default-openclaw/contract.toml`
