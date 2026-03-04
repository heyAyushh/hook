# Crates

Shared libraries for contracts, validation, and runtime execution.

## `relay-core/`

Shared core types and security-sensitive primitives:
- contract schema (`contract.rs`)
- active-profile contract validator (`contract_validator.rs`)
- envelope model (`model.rs`)
- signatures, sanitization, timestamps, keys

Docs: `crates/relay-core/README.md`

## `hook-runtime/`

Reusable runtime engine for smash execution and adapters:
- smash config parsing and validation
- Kafka consume loop and route dispatch
- egress adapter implementations
- adapter plugin execution on smash side

Docs: `crates/hook-runtime/README.md`
