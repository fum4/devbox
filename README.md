# devbox

Personal dev VPS, declared as code. One repo that captures everything needed to provision a Hetzner Cloud VM into a fully configured remote dev environment for multiple projects, driven primarily from the phone via Claude Code's Remote Control feature.

End state: from a freshly created Debian 12 VPS to *"agent on phone is editing kost on this box"* in **one command**.

```bash
ansible-playbook -i ansible/inventory.ini ansible/site.yml
```

---

## What's in this repo

```
devbox/
├── README.md            ← you are here
├── ansible/             provisioning — see ansible/README.md
│   ├── ansible.cfg
│   ├── inventory.ini.example
│   ├── group_vars/all.yml
│   ├── site.yml         top-level playbook (13 roles)
│   ├── roles/           one role per concern (base, hardening, tailscale, …)
│   └── secrets/         age-encrypted material (gitignored)
├── agents/              AGENTS.md + cross-agent skills — see agents/README.md
│   ├── AGENTS.md        always-loaded user instructions for Claude Code + Codex
│   └── skills/          on-demand capabilities (parallel-work, clone-repo, …)
├── chezmoi/             user-level dotfiles — see chezmoi/README.md
│   ├── dot_bashrc
│   ├── dot_config/zellij/config.kdl
│   └── dot_local/bin/
│       ├── executable_zj                workspace launcher (Zellij sessions)
│       ├── executable_wt                worktree + PR + merge wrapper
│       └── executable_devbox-scaffold   scaffolds .mise.toml + zellij.kdl for a new repo
├── bin/                 laptop-side utility scripts — see bin/README.md
│   └── doctor           verify the laptop is provisioning-ready
├── docs/                end-to-end setup + recovery guides — see docs/README.md
│   ├── laptop.md        fresh mac bootstrap (brew, age, ssh keys, clone)
│   ├── hetzner.md       account, payment, project, SSH key upload, server create/destroy
│   ├── tailscale.md     account, MagicDNS, OAuth client (zero-touch provisioning)
│   ├── github.md        age-encrypted GitHub identity (SSH key + PAT)
│   ├── mobile.md        phone-side apps (Tailscale, Claude, Expo Go)
│   ├── provisioning.md       the provisioning runbook (every fresh VPS)
│   └── recovery.md      incident response — when something breaks
└── repos.txt            repos cloned on every fresh provision (kost, devbox, …)
```

Each subdirectory has its own README. **Read top to bottom**: start here, then `docs/README.md` (setup + recovery), `ansible/README.md` (provisioning internals), `chezmoi/README.md` (dotfiles), and `agents/README.md` (agent instructions + skills).

## The architecture in one diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  Phone (Claude app)                                  Laptop (Ansible)       │
│  ──────────────────                                  ──────────────         │
│  drives agent via Remote Control               provisions via SSH           │
│                                                                             │
│         │ HTTPS to Anthropic                              │ SSH             │
│         │                                                 │                 │
│         ▼                                                 ▼                 │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────┐         │
│  │                    Hetzner VPS (CX33)                          │         │
│  │                                                                │         │
│  │   ┌──────────────────────┐    ┌─────────────────────────┐      │         │
│  │   │  Claude Code         │    │  Zellij sessions        │      │         │
│  │   │  (CLI agent)         │    │   ├─ kost: shell|claude │      │         │
│  │   │                      │◄───┤   │       |mobile|api   │      │         │
│  │   │                      │    │   ├─ project-2: …       │      │         │
│  │   │                      │    │   └─ project-N: …       │      │         │
│  │   └──────────────────────┘    └─────────────────────────┘      │         │
│  │                                                                │         │
│  │   tools managed via mise (per .mise.toml in each repo)         │         │
│  │   dotfiles managed via chezmoi (sources: this repo)            │         │
│  │   network: Tailscale (private mesh; no public ports but :22)   │         │
│  │                                                                │         │
│  └────────────────────────────────────────────────────────────────┘         │
│         ▲                                                                   │
│         │ Tailscale                                                         │
│         │                                                                   │
│  Phone (Expo Go) — tests in-progress mobile apps over the tailnet           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## The stack — what each piece does

| Piece | Job | Why this one |
|---|---|---|
| **Hetzner Cloud CX33** | Always-on Linux box | Cheapest credible spec (€6.49/mo, 4 vCPU, 8 GB) |
| **Debian 12** | OS | Minimal, stable, no snap/cloud-init magic |
| **Tailscale** | Private network between phone, laptop, VPS | No public ports for dev servers; works across cafés / cellular |
| **Ansible** | OS configuration as code | Idempotent, idiomatic for "configure VMs" |
| **chezmoi** | Dotfile management | Templates + permissions, applied by Ansible |
| **mise** | Per-repo tool versions, tasks, env vars | Replaces nvm + just + direnv with one config file |
| **Zellij** | Persistent workspace (tmux replacement) | Declarative KDL layouts per project; session resurrection built in |
| **Claude Code** | AI coding agent | Has Remote Control — phone drives the agent on this box |
| **Claude Squad** | Multiple parallel agents | Each on its own git worktree, no conflicts |
| **process-compose** | Headless service orchestration | For backing services (DB, Redis) when needed |
| **ntfy.sh** | Push notifications to phone | For long-running tasks ("build done") |
| **`gh` + ripgrep + fd + jq** | Tools the agent uses | Agent-facing, not human ergonomics |

---

## How to use this repo

### First-time setup (from your laptop)

1. **Provision the VPS** in the Hetzner UI (CX33, Helsinki, Debian 12, your SSH key ticked).
2. **Copy and edit the inventory:**
   ```bash
   cp ansible/inventory.ini.example ansible/inventory.ini
   # edit ansible/inventory.ini → replace <PUBLIC_IP> with the new VPS IP
   ```
3. **Bootstrap the Tailscale OAuth client** (one-time per Tailscale tenant — see [`docs/tailscale.md`](docs/tailscale.md) §6). Skipping this means falling back to the manual `TAILSCALE_AUTHKEY=tskey-...` env-var path each rebuild.
4. **Run the playbook:**
   ```bash
   ansible-playbook -i ansible/inventory.ini ansible/site.yml
   ```
5. **After the first successful run**, edit `inventory.ini` to use `ansible_user=fum4` (since the `base` role just created that user). Subsequent runs go through it.
6. **One-time Claude login**: SSH in (`ssh devbox`), run `claude`, type `/login`, complete the browser OAuth.

That's it. The box is ready.

### Daily workflow (after setup)

```bash
ssh devbox            # tailnet-aware alias (see ~/.ssh/config on your laptop)
zj kost            # attach to or create the kost workspace
                   #   ─ shell tab (ad-hoc)
                   #   ─ claude tab (auto-runs `claude`)
                   #   ─ mobile tab (auto-runs Metro via mise)
                   #   ─ api tab (start backend manually when needed)
```

Detach with `Ctrl+O` then `d`. The workspace keeps running.

From the phone: open Claude app → Code tab → tap the session → drive the agent.

### Adding a new app

Three minutes after the first one:

1. SSH to VPS, `cd ~/code && git clone <repo>`.
2. Add `.mise.toml` + `zellij.kdl` to that repo (commit them).
3. `cd <repo> && mise install` (installs the project's tool versions).
4. `zj <project>` (creates the workspace from the layout).

No central config change. Each repo carries its own dev contract.

### Recovering from VPS death

The playbook is idempotent and complete. To rebuild:

1. Hetzner UI: create a new VPS (same specs, your SSH key ticked).
2. Update `<PUBLIC_IP>` in `ansible/inventory.ini`.
3. Re-run the playbook. ~10 minutes later, identical box.

Recoverable state: code (git), dotfiles (this repo), tools (Ansible roles). Non-recoverable state without backup: anything you stored in `$HOME` that *isn't* in either git or chezmoi. There shouldn't be any — we treat the VPS as ephemeral.

---

## Conventions

- **Branch model**: `main` (no feature branches yet; we're solo).
- **Commits**: Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`).
- **Push policy**: human-authorized. Local commits free; pushes need explicit go-ahead.
- **Secrets**: never committed in plaintext. Use age-encrypted files under `ansible/secrets/` (the dominant path — Tailscale OAuth, GitHub SSH key, GitHub PAT). Env vars like `TAILSCALE_AUTHKEY` are a legacy fallback only for the pre-bootstrap case.
- **Docs as truth**: if a README disagrees with running code, the code is right and the doc is a bug. Fix the doc in the same change.

## Where things live (other repos)

| What | Where |
|---|---|
| App code (kost, future projects) | Their own GitHub repos, cloned to `~/code/` on the VPS |
| Project-specific dev contract (tasks, versions, workspace) | In each app's repo: `.mise.toml` + `zellij.kdl` |
| Personal infrastructure (this VPS) | This repo |
| Project-specific architecture docs (e.g. kost OCR flow) | Each app's own `docs/` |

## License

Personal — no license. Public mirror or fork at your own discretion.
