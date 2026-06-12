# hermes.md — evaluating Hermes Agent as the orchestration brain

> **Status: evaluation / decision phase (2026-06-12). Nothing installed.** This doc captures
> the analysis so the eventual migration doesn't re-derive it. If we adopt Hermes, this becomes
> the integration doc; if we don't, it becomes the record of why not.

[Hermes Agent](https://github.com/NousResearch/hermes-agent) is Nous Research's open-source
self-improving personal agent (MIT, 191k★, very active — checked against `v2026.6.5`). Five
pillars: **memory, skills, soul, crons, self-improvement**. It lives on a server, fronts to
messaging platforms (Telegram/Signal/WhatsApp/…), remembers across sessions, and — the headline
feature — **autonomously writes and refines its own skills** from experience.

## The proposal

Replace the hand-built "brain" layer of our orchestration with Hermes, keep everything else:

- **Layer 1 — the brain** (what Hermes replaces): the `*-control-pane` Claude sessions, the
  global memory/persona/operating-rules layer, assistant-side scheduling.
- **Layer 2 — the substrate** (what Hermes *consumes*, unchanged): `claude-spawn` + systemd
  sessions, `wt`, `zj`, `/serve`, the whole Ansible/chezmoi declarative base.

Hermes becomes the always-on concierge you text from the phone. When work is *code*, it
dispatches a Claude Code session via the existing substrate and reports back. Worker Claude
Code sessions stay exactly as they are.

## Why it fits (verified against the repo, not the marketing)

| Concern | Finding |
|---|---|
| Skills | `skills.external_dirs: [~/.agents/skills]` mounts our git-backed skills **read-only, no copying**. Hermes' self-written skills go to `~/.hermes/skills/` only — a natural staging area. Same agentskills.io `SKILL.md` standard. |
| Memory | Small + curated: `MEMORY.md` (~2200-char cap) + `USER.md`, injected per session; SQLite FTS5 only for transcript search. No import needed — seed by hand in minutes. Per-project Claude memories stay with the workers (two-tier memory is coherent, not drift). |
| Persona | `SOUL.md`. |
| Crons | Built-in scheduler with delivery to any platform. |
| Guardrails | Agent-hooks (pre-command blockers, allowlists) + `tool_loop_guardrails` — devbox laws ("no ad-hoc `apt install`", "always `wt`") can be **enforced**, not just prompted. |
| Gateway | One process, ~25 platform adapters, pairing/authz, graceful drain — systemd-friendly. We'd run it as a user unit cloned from the `claude@.service` pattern. |
| Subagents | Built-in delegation trees (depth 1–3, concurrency caps, per-child model override) — plus it can shell out to `claude-spawn` for coding. |
| Supply chain | Every dep exact-pinned (post Shai-Hulud), `uv.lock`, ships nix flake / Docker / Homebrew. We'd install via **uv + pinned release tag** in an Ansible role — not their `curl\|bash` installer. |
| Privacy | Honcho user-modeling is optional/external — leave **off**; everything else is local files + local SQLite. Secrets (`.env`, bot token, OAuth json) → `ansible/secrets/hermes-*.age`. |

The one real philosophical tension — a self-mutating agent on a declarative box — resolves
cleanly: Hermes' **config** is declarative (Ansible/chezmoi like everything else); its **learned
state** (`~/.hermes/` markdown/yaml + auto-skills) is *data*, git-backed, with promotion of
good auto-skills into `agents/skills/` as the human review gate.

## Model strategy — does the brain need a frontier model?

Auth context: Hermes supports Anthropic OAuth and can even read Claude Code's own credentials
(`agent/credential_sources.py`: `claude_code — ~/.claude/.credentials.json`), but riding the
Claude subscription is ToS-gray and shares rate limits with the coding workers. So the plan is
a **separate cheap model** for the assistant brain.

The role is *orchestration, not coding* (coding stays with Claude Code). What it actually needs:

1. **Reliable long-horizon tool calling** — the gateway loop is many small tool calls.
2. **Good judgment in two compounding loops** — memory curation (bad writes pollute every
   future session) and **skill self-authoring** (the whole point; a weak model writes garbage
   skills that compound). This is where model quality is non-negotiable.
3. *Not* needed: frontier coding/reasoning peaks.

Current numbers (June 2026): on agentic benchmarks the top open-weights models are at
last-gen-frontier level — Kimi K2.6 scores 66.7% on Terminal-Bench 2.0, ahead of Claude Opus
4.6 (65.4%), with 4,000+ sustained tool calls demonstrated; DeepSeek V4 Pro and GLM-5.1 are
just behind on the Artificial Analysis index (54 / 52 / 51). Hermes' own curated catalog
badges **`moonshotai/kimi-k2.6` as "recommended"**.

Live OpenRouter pricing (per Mtok, checked 2026-06-12 — re-verify before committing):

| Model | In | Out | Note |
|---|---|---|---|
| `moonshotai/kimi-k2.6` | $0.67 | $3.39 | **Recommended main brain** — Hermes' own pick, ≈ Opus-4.6-level agentic at ~7× cheaper |
| `deepseek/deepseek-v4-pro` | $0.43 | $0.87 | Cheapest credible main-brain alternative |
| `deepseek/deepseek-v4-flash` | $0.10 | $0.20 | **Aux-slot workhorse** (approval, curator, triage, summaries) |
| `nvidia/nemotron-3-ultra-550b-a55b:free` | $0 | $0 | Free on Nous Portal **until June 18** — zero-cost spike window |
| `nvidia/nemotron-3-super-120b-a12b:free` | $0 | $0 | Free tier on OpenRouter |
| `anthropic/claude-haiku-4.5` | $1.00 | $5.00 | If we want to stay Anthropic-native |
| `anthropic/claude-opus-4.8` | $5.00 | $25.00 | Reference — what we're *not* paying for the assistant |

Hermes has **11 separate auxiliary-task model slots** (approval decisions, skill curator,
kanban triage, profile describer, …) that default to the main model but should be pinned to a
flash-tier model — the docs explicitly say expensive models there are waste.

**Verdict:** no, we don't need Opus-class — but we *do* need frontier-**agentic** class.
The 8B-class "budget" models floating around SEO blogs are below the bar for autonomous
skill-writing; and local inference on the (CPU-only Hetzner) VPS is a non-starter. The shape:

- **Main brain:** `kimi-k2.6` via OpenRouter (~$0.67/$3.39).
- **All 11 aux slots:** `deepseek-v4-flash` (~$0.10/$0.20).
- **Spike:** `nemotron-3-ultra:free` on Nous Portal while the free window lasts (→ June 18).
- **Escape hatch:** per-message `/model` switching and per-subagent model override mean we can
  route a hard task to a Claude model ad-hoc without changing the default.

## Migration plan (when/if we go)

1. **Phase 0 — decisions** (see below).
2. **Phase 1 — declarative install**: `ansible/roles/hermes/` (uv, pinned release tag,
   Python 3.11–3.13); `hermes-gateway.service` user unit cloned from `claude@.service`;
   `~/.hermes/config.yaml` via chezmoi; secrets → age; `devbox-doctor` check.
3. **Phase 2 — brain wiring**: `external_dirs` → `~/.agents/skills`; `SOUL.md` ← persona
   ritual; `USER.md` seeded by hand; devbox laws split into SOUL prompt (judgment) +
   agent-hooks (hard rules).
4. **Phase 3 — substrate skills**: Hermes skills wrapping `claude-spawn` / `wt` / `zj` /
   `/serve` / `devbox-reprov`. Hermes delegation children for assistant work; Claude Code
   dispatch for code work.
5. **Phase 4 — cutover**: retire `*-control-pane` sessions; phone front-door moves to the
   chosen messaging platform (workers keep Claude Remote Control); rewrite `sessions.md` +
   `AGENTS.md` accordingly.
6. **Phase 5 — self-improvement loop**: tune `skills.creation_nudge_interval`; periodic
   review-and-promote of `~/.hermes/skills/` into `agents/skills/` (can itself be a Hermes cron).

Recommended entry: **side-by-side spike first** (Phase 1 only, free Nemotron window, one
project) to judge auto-skill quality before any cutover.

## Open decisions

1. **Provider/auth**: OpenRouter key (clean, metered) vs Nous Portal vs Anthropic OAuth
   (ToS-gray, shared quota). Leaning OpenRouter + Kimi K2.6.
2. **Channel**: Telegram (their most battle-tested adapter) vs Signal. Token → age either way.
3. **Hard guardrails**: which devbox laws become enforcing agent-hooks vs prompt guidance.
4. **Honcho**: off initially (external service; local-only posture).

## Sources

- [Repo](https://github.com/NousResearch/hermes-agent) — `cli-config.yaml.example`,
  `agent/credential_sources.py`, `pyproject.toml`, `website/docs/`
- [Official docs](https://hermes-agent.nousresearch.com/docs/) ·
  [model catalog manifest](https://hermes-agent.nousresearch.com/docs/api/model-catalog.json)
- Benchmarks: [Terminal-Bench 2.0 / model comparison roundup](https://medium.com/@cognidownunder/claude-opus-4-7-leads-on-code-gpt-5-5-wins-intelligence-and-kimi-k2-6-changes-everything-a01c233a0b11),
  [Kimi K2.6 guide](https://codersera.com/blog/kimi-k2-6-complete-guide-2026/),
  [open-weights coding comparison](https://www.atlascloud.ai/blog/guides/kimi-k2-6-vs-glm-5-1-vs-qwen-3-6-plus-vs-minimax-m2-7-coding-2026)
- Pricing: live OpenRouter `/api/v1/models` (2026-06-12)
