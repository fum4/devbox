# TODO — devbox

Postponed work scoped to the **devbox** repo. The convention (see
`agents/AGENTS.md` → "Postponed work goes in the repo's `TODO.md`"): anything we
consciously defer lands here, one entry per item, with enough context to pick it
up cold. Check items off or delete them when done.

---

## Secrets: deliver kost's age key to the box

**Why:** kost stores its own deploy/dev secrets encrypted in the kost repo under a
**kost-specific** age key (see kost `docs/decisions/0006-secret-handling.md`).
Those secrets are consumed *on this box* (`terraform`, `mise run dev`, `ssh
kost_vps`), so the kost age key has to be present here to decrypt them. The box
shouldn't hold the kost *secrets* — but delivering the kost *key* is the devbox's
job, the same laptop-only way it delivers its own identity. See `docs/secrets.md`
→ "Scope: this store is for the box's own secrets".

**What to do** (a devbox session, run from the laptop):

- [ ] Encrypt the **kost age private key** under the *devbox* key →
  `ansible/secrets/kost-age-key.age` (recipe: `docs/secrets.md` → "Adding a new
  encrypted secret").
- [ ] Add a small role (e.g. `kost-age-key`) that decrypts it on the controller
  (`delegate_to: localhost`, `no_log: true`) and drops it at the path kost's
  `secrets:decrypt` task expects (e.g. `~/.config/age/kost.key`, mode 0600).
  Mirror `expo-identity`'s skip-gracefully-when-no-secrets-local shape so
  `devbox-reprov` (no age key locally) stays safe.
- [ ] Wire it into `ansible/site.yml` **after `repos`** and tag it
  (`[kost-age-key, secrets]`); add a row to the `docs/secrets.md` inventory table.

> Depends on kost first generating its own age key — see kost `TODO.md`. The two
> are a pair: kost owns its encrypted secrets; the devbox delivers the key.

## Build the Hermes standalone personal/business assistant

**Why:** run Hermes Agent as a private calendar/finance/briefing concierge —
separate from the dev flows, on its own VPS. Full security-first design in
[`docs/hermes-assistant.md`](docs/hermes-assistant.md) (distinct from the
orchestration eval in `docs/hermes.md`). Deferred 2026-06-12 — design agreed,
build not started. Owner wants to spike on **Claude subscription OAuth** first
(€0), graduate to a dedicated Anthropic API key later.

**Non-negotiables (from the design):**
- Separate cheap Hetzner VPS, own Unix user, **own age key** (not devbox's, not
  accounting-sync's), Tailscale-only. No dev/GitHub/finance credentials on it.
- accounting-sync **stays on the dev box**; Hermes reads only the committed
  `backups/*.csv` via a **read-only deploy key** — never StartCo/Google
  credentials. (The `*.age` blobs are inert without the accounting age key, which
  this box deliberately won't have.)
- **Anthropic only** for this data (jurisdiction/no-train) — never a China-hosted
  API for financials. See doc's "Why not the Chinese providers".
- Read-only integrations first; messaging out to the owner only (prompt-injection
  exfiltration is the headline risk). Email triage added **last**, isolated.

**First steps:**
- [ ] Provision the separate VPS (decide: second host in this Ansible inventory
  with its own secrets bundle, vs own repo — leaning shared-repo/separate-secrets).
- [ ] Install Hermes declaratively (uv + pinned release tag, not `curl|bash`);
  systemd user unit for the gateway (mirror `claude@.service`).
- [ ] Spike on Claude OAuth; build the finance-view skill against `backups/*.csv`.
- [ ] Resolve the open decisions in `docs/hermes-assistant.md`.

## Wire up ntfy push notifications

**Why:** ntfy is installed but dormant. Phone-driven sessions would benefit from
push when a long-running task finishes (build done, /serve stack crashed, agent
needs input) instead of polling the app. Deferred 2026-06-12 — owner said "not yet".

**First step:** pick/provision a private topic (self-hosted or unguessable
ntfy.sh topic), deliver it as `NTFY_TOPIC` via the secrets flow
(`docs/secrets.md`), then decide trigger points (Claude Code Stop hooks?
process-compose lifecycle hooks?).

## Vendored skills — rejected so far

For the record (wave 1 + 2 installed 2026-06-12, see `docs/skills.md`):
`ui-ux-pro-max` (headline search-CLI broken as vendored — escaping symlinks — and its BM25 keyword-matching underwhelmed in a live demo; re-evaluate if upstream repackages), `agentspace` (ships files to external cloud — security policy), and
`github-actions-docs` (no Actions minutes; revisit if CI matters again).
