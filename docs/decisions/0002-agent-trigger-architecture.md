# 0002. Agent trigger architecture

**Status**: Accepted
**Date**: 2026-05-19
**Supersedes**: —

## Context

The devbox needs a story for **how agents get triggered to do work**. Triggers come from many sources:

- The user typing prompts in the phone Claude app (already works via Remote Control)
- The agent itself, deciding to use `wt new` when starting a new feature
- External events: GitHub issue created with a specific label, PR merged, PR comment with `@bot`, Linear ticket assigned, scheduled cron, direct `curl` from a phone shortcut, …

The question is what mechanisms to commit to building, and in what order.

## Options considered

### A. Pure cron polling

Background scripts run every N minutes, check for new work via `gh` / Linear API, spawn agents.

**Pros**: zero inbound network, no public endpoint, simple, fully under our control.
**Cons**: latency (≤ N min), wasteful API calls, hard to react to non-state-changing events, idempotency must be enforced in the script.
**Fit**: low-frequency events, latency-tolerant.

### B. Webhook receiver via Tailscale Funnel

A small Hono/Bun service on the VPS, exposed publicly at `<host>.<tailnet>.ts.net` via [Tailscale Funnel](https://tailscale.com/kb/1223/funnel). External services (GitHub, Linear) POST events. The receiver verifies HMAC, filters, dispatches via `wt`.

**Pros**: real-time, no polling, multi-source.
**Cons**: a service must stay up (systemd unit), HMAC verification to write, more attack surface (mitigated: Funnel gives TLS and DDoS protection, and only specific routes are exposed).
**Fit**: latency-sensitive triggers, multi-source futures.

### C. Queue-based (Redis / BullMQ)

The receiver enqueues; a separate worker consumes. Adds dedupe, retries, rate limiting.

**Pros**: survives bursts, retries, dead-letter handling.
**Cons**: extra moving parts.
**Fit**: high-volume or expensive-to-process events. Not us, not yet.

### D. Direct self-API

Same plumbing as B but the user invokes it directly via `curl` from a phone shortcut or browser bookmarklet. No external integration required.

**Pros**: shipping "trigger from anywhere" via iOS Shortcut / share sheet in a single afternoon.
**Cons**: same service-up requirement as B; just simpler filter logic.

## Decision

**Phase 1 (now)**: Event-triggered local wrappers, no listener service. Implemented via `wt`:

- `wt new` fetches origin, branches from `origin/<default>`
- `wt pr` fetches, rebases, force-push-with-lease, opens PR via `gh`
- `wt merge` merges PR + cleans up worktree
- `wt prune` cron (30 min) sweeps PRs merged outside `wt merge`

Triggers come from the user prompting agents directly. No external listener.

**Phase 2 (when needed)**: Webhook receiver via Tailscale Funnel. Single Hono service on Bun (consistent with the kost stack), running under a systemd user unit. The receiver:

1. Receives webhook events (GitHub, Linear, …)
2. Verifies HMAC signatures
3. Filters by event type / label / target
4. Dispatches via the existing `wt` infrastructure (creates a worktree, builds a prompt, spawns Claude Code via the official SDK or Claude Squad)

This adds support for:

- "Label an issue `agent-ready` → agent picks it up within seconds"
- "Comment `@bot fix this` on a PR → agent investigates and pushes a fix"
- "Direct dispatch from a phone shortcut" (Option D folded in)

**Phase 3 (probably never)**: Queue-based. Build only if Phase 2's volume justifies it.

## Why not all at once

Phase 2 is real infrastructure: a service to write, configure, monitor, and secure. Building it before there's a concrete event we want to act on guarantees over-engineering. The `wt` wrappers from Phase 1 are deliberately **forward-compatible** — Phase 2's dispatcher calls the same `wt` scripts.

## Rejected

- **Cron-only polling for everything**: latency too high for "new issue → agent works in seconds" UX.
- **Webhook on public IP**: violates the no-public-ports policy. Tailscale Funnel gives us the same capability without exposing the VPS.
- **Email-based triggers**: niche, fragile, hard to verify identity.

## Consequences

- The `wt` scripts in `~/.local/bin/wt` are the entrypoint for both human and event-driven flows. Anything that wants to "start a feature" or "open a PR" or "merge and clean up" goes through `wt`.
- The Phase 2 receiver lives in its own repo (likely `~/code/agent-bot`), not in this one. This repo provisions the infrastructure (Tailscale Funnel config, systemd unit, secrets) but doesn't host the service code.
- A Hono service on Bun is the committed shape — same stack as kost. Consistent technology choices reduce learning surface.
- Skill descriptions in `~/.agents/skills/parallel-work/` reference `wt`, so agents learn the wrappers via both AGENTS.md (always loaded) and the skill (on-demand for new-feature flows).

## Triggers to revisit this decision

- First concrete external trigger arrives (someone wants "label this and the agent picks it up")
- Webhook source emerges that's hard to fit through Tailscale Funnel (e.g., requires inbound TCP, not HTTPS)
- `wt prune` cron starts feeling too laggy (move to webhook-driven cleanup)
