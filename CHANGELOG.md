# Changelog

All notable changes are tracked from merged commit history.

This file is commit-driven:
- Source of truth: `git log` on `main`
- Grouping: date + conventional commit intent (`feat`, `fix`, `refactor`, `build`, `docs`, `ci`, `chore`)
- Ordering: newest first

Last generated from commits: `2026-03-04`.

## 2026-03-04

### Added
- Contract-driven serve/smash runtime model with profile-activated adapters and routes (`3dfdd47`).
- New runtime crate and adapter execution boundary for smash plus ingress/egress extensibility (`3dfdd47`).
- Operator skills for release, pipeline debug, contract authoring, and onboarding workflows (`d78d65e`, `fe7f8e3`).
- Expanded technical documentation set for architecture, configuration, deployment, security, plugins, and adapters (`28fa418`).

### Changed
- Serve package/binary naming migrated from `webhook-relay` to `hook-serve` across crate metadata, runtime references, and operator tooling (`dbad33b`).
- Deployment naming updated to `hook-serve` across Docker, Nginx, systemd, and Firecracker service assets (`0f9d120`).
- Release/publish automation updated for `hook-serve` package and artifact naming (`e96b3f0`).
- Ops scripts centralized behind `hook` infra command entrypoints (`816f403`).

### Documentation
- Spec/references were consolidated under `docs/` and release publishing docs were expanded (`164f724`, `1beab4d`).
- README and role-oriented docs were refreshed to reflect serve/relay/smash architecture and `hook-serve` naming (`16de351`, `45cd194`, `532a3db`).
- Workspace guidance and skills were aligned with the renamed serve runtime (`45cd194`, `532a3db`).

## 2026-03-03

### Added
- Configurable Kafka authentication settings for consumer paths (`4dceb2f`).
- Verbose relay and consumer pipeline logging for better observability (`7f0ada1`).
- Release and crates publishing automation scaffolding (`9cb9e97`).
- Crate metadata and build prep for registry publishing (`91d9e76`).

### Fixed
- Firecracker boolean parsing compatibility for Bash 3 environments (`5bf1f31`).

### CI
- Release/publish automation was temporarily disabled pending readiness (`d6d57ea`).

## 2026-03-02

### Documentation
- Firecracker runtime behavior and opt-in proxy composition documentation expanded (`b09619f`).

## 2026-02-28

### Added
- Firecracker watchdog, diagnostics, and hardening improvements (`a0a23bd`).

## 2026-02-27

### Added
- Composable Firecracker runtime and host orchestration support (`189a2e0`).

## 2026-02-26

### Fixed
- Firecracker run helper launch and log fallback behavior hardened (`610d6c9`).

## 2026-02-22

### Fixed
- Kafka plaintext usage now requires explicit opt-in (`ccda3c6`).
- Webhook sanitization changed to non-destructive behavior (`afc365c`).

### Refactored
- Consumer forwarding path moved to mapped coder hook flow (`a54e117`).

## 2026-02-21

### CI
- Added required libcurl headers in CI for `rdkafka` builds (`fab9e41`).

### Documentation
- Added modular crate skills and component guides (`ae3b754`).

