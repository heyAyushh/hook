# Roadmap

Last updated: 2026-03-04

## Current State

Implemented:
- Contract-driven `serve -> relay -> smash` runtime model
- Active-profile contract validation (strict fail-closed default)
- Plug-and-play ingress and egress adapters
- Symmetric plugin execution on both sides (`serve` + `smash`)

## Near-Term (P1)

1. Profile hardening and fixtures
- Add more app contracts under `apps/` for common deployment profiles.
- Add fixture matrix tests for profile validation and projection.

2. Runtime integration tests
- Add end-to-end tests for mixed ingress/egress combinations.
- Add explicit required-vs-optional destination commit semantics tests.

3. Operator UX consistency
- Standardize role command outputs (`serve`, `relay`, `smash`) for startup summaries and validation reports.
- Add stable JSON output schema for automation.

## Mid-Term (P2)

1. Adapter observability
- Per-adapter metrics and plugin counters.
- Route-level and adapter-level latency/error histograms.

2. Config ergonomics
- Better profile discovery and contract linting commands.
- Contract scaffolding templates for new apps/adapters.

## To Be Added (Requested)

1. External plugin crates (opt-in)
- Keep internal plugins as default path.
- Add optional external plugin execution model with hard controls:
  - pinned plugin version/artifact
  - signature/hash verification
  - sandboxed runtime boundary (WASM or isolated process)
  - capability allowlist
  - strict startup failure for invalid active external plugins

## Long-Term (P3)

1. Adapter SDK and extension model
- Formal adapter/plugin SDK for internal and vetted external extensions.
- Compatibility guarantees and versioning policy.

2. Reference profile catalog
- Publish maintained profile catalog with tested combinations and deployment notes.
