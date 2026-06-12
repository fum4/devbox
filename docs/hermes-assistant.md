# hermes-assistant.md — Hermes as a standalone personal/business assistant

> **Status: design / not yet built (2026-06-12).** A security-first plan for running
> [Hermes Agent](https://github.com/NousResearch/hermes-agent) as a personal life/business
> assistant — **entirely separate** from the devbox dev flows.
>
> This is a *different system* from the orchestration evaluation in [`hermes.md`](hermes.md).
> That doc asks "should Hermes replace our control-pane brain?" (answer: probably not). This
> doc is the thing we're actually doing: a private concierge for calendar / finance-view /
> briefings that never touches the coding stack.

## What it is

An always-on Hermes gateway you text from your phone (Telegram/Signal) that knows your
calendar, your business finances (read-only view), and your day — and gets more useful over
time via its memory + self-improvement. **It does no coding and lives nowhere near the code.**

The design is dominated by **one principle**: this agent holds sensitive personal/financial
data, ingests untrusted input, and can send messages — so every decision is a data-security
decision first and a feature decision second.

## Where it runs: its own VPS, its own identity

A **separate cheap VPS** (~€4/mo Hetzner), not the devbox. Rationale = blast radius: a
compromise of the assistant must not reach your source code, your GitHub identity, or the dev
box. Concretely:

- **Own Unix user, own host, own secrets bundle** with its **own age key** — *not* the devbox
  age key, *not* the accounting-sync age key. (Per-repo/per-host key model, same as we already
  do — see accounting-sync `secrets/README.md`.)
- **Tailscale-only**, never public. Phone reaches it over the tailnet; no inbound but SSH.
- **Does NOT hold**: the devbox GitHub SSH identity, the accounting-sync age key, any
  StartCo/bank/Google service-account credential.
- **Declarative still applies**: the box should be reproducible. Open question whether it's a
  second host in the existing devbox Ansible repo (convenient, declarative) or its own repo
  (cleaner separation). Leaning: second host entry in the devbox Ansible inventory, but with a
  wholly separate secrets bundle + age recipient, so it shares *patterns* not *credentials*.

## The finance data boundary (the important part)

accounting-sync **stays on the dev box.** It is a manually-run build tool that holds a Google
service-account key; that's dev work and that credential belongs on the dev side. Hermes never
gets accounting-sync's credentials.

What Hermes gets instead: the **already-committed sanitized snapshots** accounting-sync
publishes — `backups/*.csv` (income, expenses, dashboard, trimestre, lunar). These contain
numbers only: no money movement, no API keys (accounting-sync ADR 0003 confirms the worst-case
residual is a sheet-scoped Google SA, which stays on the dev side).

```
dev box                                   hermes VPS (separate)
─────────                                 ────────────────────
StartCo key (never stored, revoked)
Google SA key (age-encrypted, stays)
        │
        ▼
accounting-sync  ──produces──▶ backups/*.csv ──read-only git──▶  Hermes reads CSVs
        │                      (committed, sanitized)             (numbers only)
        ▼
secrets/*.age (env, google SA)  ──── NOT readable on hermes VPS ────┘
   (hermes box lacks the accounting age key → cannot decrypt even if cloned)
```

- Access mechanism: a **read-only deploy key** scoped to the accounting-sync repo (or sync only
  `backups/`). Even a full clone is safe — the `*.age` blobs are undecryptable without the
  accounting age key, which the Hermes box deliberately does not have.
- Result: a breach of the Hermes box leaks a **stale CSV of figures**, never a credential or a
  way to move money. This extends ADR 0003's "no key at rest" discipline one hop outward.

## Threat model

| Threat | Mitigation |
|---|---|
| **Prompt-injection exfiltration** — a malicious email / web page / calendar invite tells the agent to leak finances or send money | Read-only integrations first; no auto-send to arbitrary recipients (messaging out to **you** only); treat any tool that reads external content as session-tainting; keep finance-reading and untrusted-input-reading in **separate sessions/profiles** where possible |
| **Credential blast radius** — box compromise | Separate VPS, own user, own age key, no dev/GitHub/finance credentials present; Tailscale-only |
| **Provider data egress** — your financials sent to a model host | Anthropic only (Western jurisdiction, contractual no-train). **Never** a China-hosted API for this data — see below |
| **Stale/wrong data** — agent reasons on old CSVs | CSVs carry their backup date; agent surfaces "as of" in answers |
| **Self-written skills go rogue** — autonomous skill creation touches sensitive flows | Auto-skills land in `~/.hermes/skills/` (its own dir); review before any that touch finance/messaging are trusted; hard agent-hooks block dangerous commands |

## Provider / model decision

**Anthropic (Claude), full stop — for the data-trust reason, not cost.** This is the inverse of
the orchestration doc: there, cheap open-weights (Kimi K2.6) win because the data is your own
source. Here the data is your **company financials + calendar + correspondence**, so jurisdiction
and no-train guarantees dominate price.

Rollout:
1. **Spike on Claude subscription OAuth** (reads `~/.claude/.credentials.json`, auto-refreshes) —
   €0 to feel whether the assistant is actually good. Caveats: shares rate limits with coding
   workers; relies on Hermes' CC-identity spoofing (fragile). Fine for a trial.
2. **Graduate to a dedicated Anthropic API key** once it earns its place — same provider, same
   model, same behavior, only the auth credential changes (zero rework). Gives it its own quota,
   own billing, own blast radius, and drops the ToS-grey spoofing path.

### Why not the Chinese providers (the curiosity, recorded)

Not a quality knock — Kimi/DeepSeek are excellent. The issue is the **hosted API** for sensitive
data:

- **Legal compulsion**: China's National Intelligence Law (2017) Art. 7 compels orgs to assist
  state intelligence; DSL/PIPL add access levers. Data on a China-hosted endpoint is potentially
  state-reachable with no recourse for a foreign user.
- **Weaker data terms**: looser/less-transparent no-train + retention commitments than
  Anthropic/OpenAI business tiers.
- **Key nuance**: these are *open-weight* models — "Chinese model" ≠ "data goes to China." Self-host
  the weights → zero egress; a Western host (e.g. via OpenRouter) → data goes to that host's
  jurisdiction, not Beijing. The danger is specifically the **China-hosted hosted API**.
- **Verdict**: irrelevant risk for coding-orchestration over your own source; a real risk for
  plaintext financials. For this box, Claude removes the question entirely.

## Integration roadmap (read-only first, expand deliberately)

1. **Finance view** — read `backups/*.csv`; answer "runway, what's owed, overdue invoices, VAT
   due when." Read-only. *(First thing to build — the boundary is already clean.)*
2. **Calendar** — Google/CalDAV **read** first ("what's today / this week"). Write (create events)
   only after the read path is trusted.
3. **Briefings** — Hermes cron → Telegram: morning "today + runway + due dates."
4. **Email triage** — **highest injection risk**; add last, read-only, and isolate from the
   finance session.

## Open decisions

1. **VPS provisioning**: second host in devbox Ansible (shared patterns, separate secrets) vs its
   own repo. Leaning shared-repo/separate-secrets.
2. **Channel**: Telegram (most battle-tested adapter) vs Signal.
3. **Finance access mechanism**: read-only deploy key on the whole repo vs syncing only
   `backups/`. Leaning deploy-key (simpler; `.age` blobs are inert without the key).
4. **When to graduate** OAuth → dedicated Anthropic API key.

## Sources

- [Hermes Agent repo](https://github.com/NousResearch/hermes-agent) — `agent/anthropic_adapter.py`
  (OAuth/CC-credential path), `cli-config.yaml.example`
- accounting-sync `docs/decisions/0003-no-automation.md`, `secrets/README.md` (the data posture
  this design extends)
- Jurisdiction: China National Intelligence Law (2017), Data Security Law, PIPL
