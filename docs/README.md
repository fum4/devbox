# docs/

Everything you need to set up the devbox from scratch — laptop, Hetzner, Tailscale, GitHub identity, phone — and to recover when something breaks.

## Read order, by scenario

### Brand new everything (no laptop, no accounts, no devbox)

1. [`laptop.md`](laptop.md) — Mac setup, install tools, SSH keys
2. [`hetzner.md`](hetzner.md) — Hetzner Cloud account + project + SSH key + every server-create/destroy in the UI
3. [`github.md`](github.md) — Generate the **age keypair** (`secrets.local`) + bootstrap the age-encrypted GitHub identity
4. [`tailscale.md`](tailscale.md) — Tailscale tenant, MagicDNS, OAuth client (reuses the age recipient from step 3)
5. [`provisioning.md`](provisioning.md) — Provision the first VPS
6. [`mobile.md`](mobile.md) — Phone-side apps (Tailscale, Claude, Expo Go)

About 90 minutes start-to-finish if nothing snags. **Step 3 before step 4** — Tailscale's OAuth bootstrap encrypts a secret using the age recipient that github.md generates.

For the cross-cutting "how do encrypted secrets work in this repo" reference, see [`secrets.md`](secrets.md). Steps 3 and 4 both use the pattern described there.

### Lost laptop, accounts and secrets still intact

1. [`laptop.md`](laptop.md) — sets up the new laptop, restores `secrets.local` from password manager
2. [`provisioning.md`](provisioning.md) — re-provision the VPS so it accepts the new laptop's SSH key (or step 5 in `recovery.md` to keep the same VPS)

### Same laptop, just rebuilding the VPS

[`provisioning.md`](provisioning.md) — the runbook. ~15 min.

### Adding a new app to an existing devbox

Not a docs flow — use the `clone-repo` skill on the devbox itself. Either tell the agent ("clone X and set it up") or follow the manual recipe in [`../agents/skills/clone-repo/SKILL.md`](../agents/skills/clone-repo/SKILL.md).

### Something's broken

[`recovery.md`](recovery.md) — symptom matrix: SSH/gh broken, claude offline, playbook failing, etc.

## What's in each doc

| Doc | Audience | What it produces |
|---|---|---|
| [`laptop.md`](laptop.md) | Fresh / replaced Mac | Laptop ready to run `ansible-playbook` |
| [`hetzner.md`](hetzner.md) | First-time Hetzner user; every server create/destroy | Account ready, server running with SSH key pre-installed |
| [`tailscale.md`](tailscale.md) | First-time Tailscale user | Tailnet up, MagicDNS on, laptop + phone connected, OAuth client bootstrapped for unattended provisioning |
| [`secrets.md`](secrets.md) | Anyone touching `ansible/secrets/`, anyone restoring on a new laptop | Understanding of the encryption pattern + new-laptop restore recipe + how to add new secrets |
| [`github.md`](github.md) | First-time, or rotating secrets | Age-encrypted SSH key + PAT in the repo, public key registered on GitHub |
| [`provisioning.md`](provisioning.md) | Every VPS provision | Fully configured VPS, agents driveable from phone |
| [`mobile.md`](mobile.md) | New phone, or after reinstall | Tailscale + Claude + Expo Go ready |
| [`sessions.md`](sessions.md) | Anyone hosting agent sessions or dev servers | How sessions (systemd+dtach) and dev servers (process-compose) are supervised; spawn / attach / restore / migrate |
| [`recovery.md`](recovery.md) | Incident response | Symptom → cause → fix matrix |

## Things NOT in this directory

- **High-level design** (why we picked this stack): in commit history + the source-level READMEs (root, `ansible/`, `agents/`, `chezmoi/`).
- **Per-project setup** (how to run kost specifically, etc.): in each project's own repo.
- **Skill definitions** (`parallel-work`, `clone-repo`): in [`../agents/skills/`](../agents/skills/), loaded on-demand by Claude / Codex.
- **Ansible role internals**: each role's `tasks/main.yml` is its own documentation.

## Conventions in these docs

- **Commands assume macOS** on the laptop and **Debian 12** on the VPS. If you're on Linux laptop or different OS, mostly find-and-replace `brew install` → your package manager.
- **All paths use `~/_work/devbox`** for the devbox repo checkout. If you cloned elsewhere, adjust.
- **`fum4`** is the example username throughout. If you're a different user, adjust.
- **`devbox`** is the canonical SSH alias + Tailscale machine name. Defined in `~/.ssh/config` Host block + Tailscale MagicDNS.
- **`secrets.local`** is the age private key file at the devbox repo root. Gitignored via `*.local`. Backed up to your password manager.
- **`*.age` files** are encrypted secrets, committed to the repo. Safe to share alongside the repo since they need `secrets.local` to decrypt.

## Adding a new doc

If you find yourself doing the same setup-or-recovery thing twice and it doesn't fit any existing doc, add one. Stay flat (no subdirs), short URLs, descriptive filenames. Cross-link from `README.md` (this file) so future-you finds it.

Stale docs are worse than no docs. If a doc and the running setup disagree, the setup is right — fix the doc as part of the same change.
