# References Index

Operational runbooks, integration guides, and source-specific references for the `hook serve/relay/smash` runtime.

---

## Hook Runtime

- [Hook CLI and Contract Reference](hook-definition.md) — `hook` commands, contract.toml schema, all adapter drivers and config keys
- [Boot Verification](boot.md) — pre-flight checks, startup order, health endpoints, smoke test

## Source Handlers

- [GitHub Webhook Source](github-hooks.md) — HMAC setup, GitHub App creation, event subscription, feedback loop prevention, outbound auth
- [Linear Webhook Source](linear-hooks.md) — HMAC setup, timestamp window, Linear webhook configuration, agent identity

## Delivery

- [OpenClaw Delivery](openclaw-relay.md) — `openclaw_http_output` adapter, OpenClaw hooks config, transform modules, DLQ behavior
- [Payload Sanitization](payload-sanitization.md) — threat model, defense layers, `relay_core::sanitize` integration, testing injections

## Deployment

- [Tailscale Deployment](tailscale.md) — exposing `hook serve` via Funnel, MagicDNS for multi-node, systemd units, proxy headers

## Setup

- [First-Time Setup Guide](setup-wizard.md) — interactive questionnaire for first-time stack setup, file generation, post-setup checklist

## Publishing

- [Release and Publishing Runbook](release-publishing.md) — binary release flow, crate publish order, rollback

## OpenClaw Agent Integration

- [OpenClaw Agents](openclaw-agents.md) — agent profiles, SOUL.md, TOOLS.md, session model
- [OpenClaw Subagents](openclaw-subagents.md) — subagent patterns, delegation, context passing
- [Agent Orchestrator](agent-orchestrator.md) — multi-agent orchestration patterns

---

## Main Documentation

For full architecture and configuration reference, see [../README.md](../README.md).
