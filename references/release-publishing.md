# Release and Publishing Runbook

## Scope

This repository publishes:

- Binary artifacts (`webhook-relay`, `kafka-openclaw-hook`) to GitHub Releases
- Crates (`relay-core`, `webhook-relay`, `kafka-openclaw-hook`) to crates.io

## Prerequisites

- Version bump committed in all relevant `Cargo.toml` files
- CI green on `main`
- `CARGO_REGISTRY_TOKEN` configured in GitHub Actions secrets for crates publishing

## Local Validation (Required)

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo build --workspace --release
scripts/build-release-binaries.sh
scripts/publish-crates.sh --dry-run
```

## Binary Release Flow

1. Tag and push:

```bash
git tag v0.2.0
git push origin v0.2.0
```

2. Workflow `.github/workflows/release-binaries.yml` runs automatically.
3. Artifacts and SHA256 files are attached to the GitHub release.

## Crates Publish Flow

1. Open GitHub Actions -> `Publish Crates`.
2. Run with:
   - `dry_run = true` first
   - then `dry_run = false` to publish
3. Select which crates to publish for partial releases.

Publish order is enforced:

1. `relay-core`
2. `webhook-relay`
3. `kafka-openclaw-hook`

## Best Practices

- Never publish from an untagged or dirty release state.
- Keep crate versions synchronized with dependency versions when using local path+version dependencies.
- Publish `relay-core` first; downstream crates depend on it.
- Keep release artifacts immutable; do not replace files under an existing tag.
- Use dry-run publish on every release candidate.

## Rollback Notes

- crates.io publish is immutable (cannot overwrite version).
- If a bad release is published:
  - yank affected crate versions
  - cut a new patch version
  - republish and update release notes
