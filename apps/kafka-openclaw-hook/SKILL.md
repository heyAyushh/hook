---
name: kafka-openclaw-hook
description: >
  Maintain the kafka-openclaw-hook compatibility binary and its integration with
  hook-runtime smash execution. Use when changing startup wiring, runtime env
  expectations, deployment compatibility, or smash adapter/plugin behavior.
---

# kafka-openclaw-hook Skill

## Scope

- `apps/kafka-openclaw-hook/src/main.rs`: compatibility entrypoint
- `crates/hook-runtime/src/smash/*`: smash runtime behavior
- `crates/hook-runtime/src/adapters/egress/*`: egress adapter drivers

## Guardrails

- keep compatibility process name and startup path stable
- maintain at-least-once delivery semantics for required destinations
- preserve DLQ behavior for required delivery failures
- keep secrets/token values out of logs

## Change Workflow

1. Edit only the owning runtime module.
2. Keep adapter/plugin behavior explicit and test-backed.
3. Update docs if env keys or driver semantics change.
4. Run:
- `cargo fmt --all`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test -p hook-runtime`
- `cargo test -p kafka-openclaw-hook`

## References

- `apps/kafka-openclaw-hook/README.md`
- `crates/hook-runtime/README.md`
- `apps/default-openclaw/contract.toml`
