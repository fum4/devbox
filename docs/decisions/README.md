# docs/decisions/

Architecture Decision Records (ADRs). Append-only, dated, each one captures the **context, decision, and consequences** for a non-trivial design choice.

## Why ADRs

Decisions get made in conversation and then forgotten. Three months later we don't remember *why* we picked X over Y, and we re-litigate or quietly drift. ADRs are the cure: write down the option space, what we chose, and what we'd need to see to revisit. The next person (or future you) reads the ADR and knows the state of the world.

## Format

Numbered, dated, with a short slug:

```
NNNN-<kebab-slug>.md
```

Each ADR has these sections:

- **Status** — Proposed / Accepted / Superseded by NNNN / Deprecated
- **Date** — when accepted
- **Context** — what problem are we solving
- **Options considered** — the menu, with pros/cons
- **Decision** — what we picked
- **Rejected** — what we considered and ruled out, with reasoning
- **Consequences** — what follows from this choice
- **Revisit triggers** — events that would warrant reopening the decision

## Rules

- **Append-only.** Never edit an ADR after it's accepted. If a decision changes, write a new ADR that supersedes the old one (mark the old as `Superseded by NNNN`).
- **One concern per ADR.** Two unrelated decisions get two files.
- **Number monotonically.** No re-numbering.
- **Date in `YYYY-MM-DD`.**

## Current ADRs

| # | Title | Status |
|---|---|---|
| [0002](0002-agent-trigger-architecture.md) | Agent trigger architecture: event-triggered now, webhooks later | Accepted |

(ADR 0001 lives implicitly in `docs/plan.md` — the locked-in tool stack. If a future decision reopens any of those choices, the new ADR cites and supersedes the relevant sections of plan.md.)
