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

## Terraform-provision the devbox VPS — Phase 1 merged (PR #12); your Phase 0 + 2 remain

`terraform/devbox/` is on main; it adopts the *running* box via `import` (no
rebuild). What's left needs **you** (browser + laptop) — full runbook:
`docs/terraform.md` → "One-time bootstrap":

- [ ] R2 bucket **`devbox-backup`** (EU) + an **Account API token** scoped to it
  (Object R&W). Hetzner **R/W API token** in the devbox project.
- [ ] On the laptop: **age-encrypt both** into `ansible/secrets/`
  (`hetzner-token.age`, `r2-devbox-state.age`) — bootstrap step 3 has the exact
  commands. No Bitwarden entries, no plaintext files (secrets.md hard rule).
- [ ] `bin/devbox-tf init` → import the 3 live resources → `plan` clean → `apply`
  (bootstrap step 4). Ping the `devbox-terraform` session if the plan shows
  anything destructive.

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
