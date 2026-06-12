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

## Provision the devbox VPS via Terraform

**Why:** the box's *configuration* is fully declarative (Ansible/chezmoi), but its
*existence* is still hand-clicked in the Hetzner UI (`docs/hetzner.md` §4–5) — the
last click-ops island. Terraform makes the box itself declarative: a thin layer
**below** Ansible (TF owns "the box exists + how to reach it + the edge firewall";
Ansible keeps owning everything inside, unchanged). Headline win: a **stable
primary IP** that survives rebuilds → `~/.ssh/config` + `ansible/inventory.ini`
become static files, killing the per-rebuild `ssh-keygen -R` / edit-config /
edit-inventory churn. Analysed 2026-06-12; mirrors tipso's proven
`infra/terraform/` (R2 state backend, gitignored-tfvars-from-Bitwarden creds).

**Decisions locked (2026-06-12):**
- Config lives at **`terraform/devbox/`** (sibling of the staged `terraform/hermes/`;
  one dir per machine — `terraform/<machine>/`).
- State in a **new, separate R2 bucket `devbox-backup`** (parallel to `tipso-backup`;
  key `terraform/devbox.tfstate`) — keeps devbox self-contained, no tipso coupling.
  Bucket is created out-of-band (bootstrap exception — holds TF's own state).
- **Add a Hetzner Cloud Firewall** (1 inbound rule: SSH/22; Tailscale needs nothing
  inbound) — edge filtering, strictly better than on-box ufw; **keep ufw too** (layered).
- TF creds are **lane 2** (laptop-only, TF-consumed): `terraform.tfvars` (HCLOUD_TOKEN)
  + `.r2-backend.env` (R2 keys), both gitignored mode 0600, backed up to Bitwarden.
  **Not** the age store (that's lane 1 — Ansible-delivered box-identity secrets).
- hcloud provider `~> 1.65` (latest), terraform `>= 1.9`. hcloud provider only
  (no Vercel/Cloudflare provider, no Coolify cloud-init, no workspaces — all simpler
  than tipso).

**Plan (do in a worktree — `wt new terraform-provisioning`):**
- [ ] **Phase 0 (manual):** create R2 bucket `devbox-backup` + its access key; create a
  Hetzner R/W API token in the devbox project. Store all in Bitwarden; write the two
  gitignored cred files.
- [ ] **Phase 1:** write `terraform/devbox/` (versions, providers, backend, variables,
  ssh-key, firewall, primary-ip, server, outputs, two `.example` files, `.gitignore`).
- [ ] **Phase 2 (adopt running box, NO rebuild):** `import` the live SSH key + server +
  its existing primary IPv4 (importing the primary IP keeps the *current* IP and just
  makes it durable via `auto_delete = false`). Tune `.tf` until `plan` = zero changes on
  imported resources; then `apply` only the two new things (firewall + the auto_delete flip).
- [ ] **Phase 3 (defer to next real rebuild):** prove `destroy -target=server` → `apply`
  yields a new box on the *same* IP, then `ansible-playbook` reconfigures it.
- [ ] **Phase 4:** `bin/devbox-tf` wrapper; rewrite `docs/hetzner.md` §4–5, trim
  `docs/provisioning.md` §1–2, new `docs/terraform.md`, update `docs/secrets.md` +
  `docs/recovery.md`; add a `bin/doctor` check; add `terraform fmt -check` + `validate`
  to CI (`.github/`).
  > NOTE: a parallel session is migrating the *global* TF-state/secrets strategy
  > (age + Bitwarden root of trust, R2 state buckets) from tipso into devbox docs +
  > root AGENTS.md (2026-06-12). When writing `docs/terraform.md` / touching
  > `docs/secrets.md`, **reference that global doc — don't duplicate it**; keep only
  > devbox-specifics here (bucket name, file paths, import sequence).

**Deferred sub-item:** factor `terraform/modules/hetzner-box` (shared server/ssh-key/
firewall/primary-ip) once **Hermes** also needs a box — rule-of-two; today devbox is the
only user. See the Hermes entry below (this unblocks its "provision the separate VPS" step).

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
  Once the devbox Terraform lands (see "Provision the devbox VPS via Terraform"
  above), Hermes gets its box from `terraform/hermes/` via the shared
  `terraform/modules/hetzner-box` module — that's the rule-of-two trigger to factor it.
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
