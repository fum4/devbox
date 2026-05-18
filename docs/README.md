# docs/

Long-form documentation for devbox: design notes, decisions, runbooks.

## What's here

- [`plan.md`](plan.md) — the master plan. Goal, constraints, the locked-in tool stack with rationale, repo layout, daily workflow, phases, and an append-only decisions log. Read this if you want the *why* behind every choice in this repo.

## When to add more

This directory is for things that **don't belong in `README.md`** (too long, too detailed, too historical) and **don't belong in code comments** (concept-level, not file-level).

Three kinds of doc fit here:

| Kind | Filename pattern | Examples |
|---|---|---|
| Architecture notes | `architecture/<topic>.md` | "Why we don't use containers", "How Tailscale + Caddy interact" |
| Decision records (ADRs) | `decisions/NNNN-<slug>.md` | "0001-pick-zellij-over-tmux", "0002-defer-codex" |
| Runbooks | `runbooks/<procedure>.md` | "Rotate Tailscale auth key", "Restore VPS from snapshot" |

Decision records are dated, append-only, and **supersede rather than edit** (write a new ADR that supersedes the old one if a decision changes).

## Stale docs are worse than no docs

If `docs/plan.md` and a running playbook disagree, the playbook is right and the doc is a bug. Fix the doc as part of the same change.

If a doc is no longer load-bearing (e.g. a runbook for a procedure we no longer use), delete it. The git history still has it.
