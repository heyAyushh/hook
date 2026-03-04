# Changelog

All notable changes to this repository are documented in this file.

## 2026-03-04

### Summary
- Moved from a tightly coupled `webhook-relay + kafka-openclaw-hook` flow to a contract-driven `serve -> relay -> smash` model.
- Added reusable runtime execution in `crates/hook-runtime` with adapter boundaries.
- Added symmetric plugin pipelines on both sides:
  - `serve` ingress plugins
  - `smash` egress plugins

### How The Change Happened
1. Introduced app-owned contracts in `apps/<app>/contract.toml` with profile activation.
2. Added active-profile contract validation in `relay-core`:
- fail-closed in `strict`
- unknown drivers tolerated only when inactive
- unsupported active drivers rejected
3. Split runtime behavior into role-oriented paths:
- `serve` ingress receives, validates, sanitizes, and publishes Kafka envelopes
- `relay` remains Kafka-core transport bridge
- `smash` consumes Kafka and dispatches to egress adapters
4. Extracted smash runtime logic into `crates/hook-runtime` and kept `apps/kafka-openclaw-hook` as a compatibility binary wrapper.
5. Added plugin parsing, validation, and execution:
- serve plugins loaded from active ingress adapter config
- smash plugins loaded from active egress adapter config
- plugin failures are fail-closed on required delivery paths

### What It Means Now
- Contract and profile selection decide runtime behavior, not hardcoded single-destination wiring.
- Kafka is the mandatory backbone between ingestion and delivery in all active profiles.
- MCP and WebSocket are optional and plug-and-play.
- Operators can keep unused adapters/drivers in contract files without breakage, as long as they are not active in the selected profile.
- Validation defaults to strict fail-closed behavior unless debug mode is explicitly selected.

### Plugin Model (Current)
Plugin drivers available for both serve and smash adapter configs:
- `event_type_alias`
- `require_payload_field`
- `add_meta_flag`

Execution semantics:
- plugins run in declaration order
- payload field requirements fail request/delivery when missing
- meta flags are deduplicated and persisted in envelope metadata

### Compatibility Notes
- Existing `kafka-openclaw-hook` operational entrypoint remains available.
- Existing default profile behavior remains `HTTP webhook -> Kafka -> OpenClaw`.
- Legacy references that describe `adnanh/webhook + relay shell scripts` are now marked as legacy documentation.

### Documentation Structure Update
- Moved repository planning/spec docs into `docs/`:
  - `docs/spec.md`
  - `docs/CHANGELOG.md`
  - `docs/roadmap.md`
- Moved reference guides under `docs/references/` and added a references index.
- Updated repository links so README, skills, and crate/app docs point to the new docs layout.
