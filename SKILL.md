---
name: hook-serve
description: >
  Build, maintain, and operate the contract-driven hook workspace with
  serve/relay/smash roles, Kafka core transport, and plug-and-play adapters.
  Use when editing runtime behavior, contract validation, adapter/plugin
  execution, or deployment documentation.
---

# Hook Serve Workspace Skill

## Workspace Map

- `src/`: serve runtime (`hook-serve`)
- `tools/hook/`: operator CLI for role execution and ops workflows
- `apps/default-openclaw/`: canonical compatibility contract
- `apps/kafka-openclaw-hook/`: compatibility wrapper binary for smash runtime
- `crates/relay-core/`: contracts, validator, shared envelope/security primitives
- `crates/hook-runtime/`: smash runtime and adapter execution engine
- `config/kafka-core.toml`: Kafka core config reference
- `systemd/`, `firecracker/`, `scripts/`: deployment and operations

## Use This Skill To

- evolve contract schema and profile semantics
- implement or validate serve ingress adapter behavior
- implement or validate smash egress adapter behavior
- add or change plugin execution semantics on either side
- tune fail-closed validation and runtime safety defaults
- update operator docs and runbooks after behavioral changes

## Safety Invariants

- strict fail-closed validation unless debug mode is explicit
- unsupported drivers rejected only when active in selected profile
- Kafka remains mandatory transport between serve and smash
- do not log sensitive secrets/tokens
- preserve required-destination delivery semantics for smash

## Fast Workflow

1. Make the smallest change in the owning module.
2. Update contract/runtime docs when behavior changes.
3. Run:
- `cargo fmt --all`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace`

## Key Docs

- `README.md`
- `docs/CHANGELOG.md`
- `docs/spec.md`
- `tools/hook/README.md`
- `crates/relay-core/README.md`
- `crates/hook-runtime/README.md`
