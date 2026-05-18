# devbox plan — multi-repo dev VPS with Claude Code

Master plan for a personal Hetzner VPS used as a remote dev environment for multiple repos, driven primarily from the phone via Claude Code's Remote Control feature.

This is the source of truth. Update it when decisions change; do not let it go stale.

---

## Goal

A single VPS that hosts all personal projects (currently kost; will grow). The agent (Claude Code) lives on the VPS, runs in a persistent workspace, and is driveable from the phone Claude app. Mobile testing (Expo Go) reaches the VPS via Tailscale. Adding a new app should be ~3 minutes after the first one.

Optimize for: DX, declarative config, ease of rebuild from scratch.

## Constraints

- Single user, single VPS (may upgrade hardware; not multiplexing across users)
- Budget: ~€10/month base infra (currently €6.49 on Hetzner CX33)
- Linux + bash native; no interest in 1000-line YAML setups or heavy abstractions
- Pre-launch (kost is pre-v1) → cleanliness > backwards compatibility
- Phone is the primary control surface; laptop is secondary

## Out of scope

- Production deploys (kost → Fly.io stays in existing CI/CD; this box is dev-only)
- Multi-machine fleets (one VPS, full stop, until proven otherwise)
- Public-facing services on the VPS (Tailscale-only access)
- Codex CLI (no Linux remote-control as of 2026-05; revisit later)
- MCP servers (defer until concrete project need)
- Terraform / Nix / Kubernetes / Ansible Tower

---

## The stack (locked-in decisions)

| Layer | Tool | Why |
|---|---|---|
| **Provisioning (IaaS)** | Hetzner UI (manual) | One VPS; UI is faster than Terraform at scale 1 |
| **OS config** | Ansible | Idempotent, declarative, replaces the manual runbook |
| **Network** | Tailscale | Private mesh; no public ports except SSH |
| **Workspace persistence** | Zellij | Declarative KDL layouts, built-in session resurrection, mouse + status bar by default |
| **Task / tool versions / env** | mise | Per-repo `.mise.toml`; consolidates versions, tasks, env vars |
| **Parallel agents** | Claude Squad | Multiple Claude/Codex sessions on isolated git worktrees |
| **Headless services** | process-compose | Declarative YAML for backing services (Postgres/Redis/workers) |
| **Dotfiles** | chezmoi | Templated, idempotent, multi-machine; managed inside this repo |
| **Notifications** | ntfy.sh | Phone push notifications via HTTP — installed dormant |
| **Agent tools** | ripgrep, fd, jq, gh | Tools the agent itself reaches for |
| **Secrets (deferred)** | sops + age | Encrypted at rest, age key in 1Password/Bitwarden |
| **AI agent** | Claude Code | Remote Control works on Linux; phone-driveable |

## Tools considered and rejected

| | Reason |
|---|---|
| tmux + tmuxinator | Worked, but Zellij wins on declarative layouts + DX |
| Terraform | One VPS; UI is faster |
| Codex CLI | No Linux Remote Control (Mac-only pairing). Revisit when OpenAI ships Linux support |
| Nix / devbox / flox | Heavy abstraction; mise covers 90% with 10% friction |
| Docker Compose for dev | Wrong layer; kost is monorepo on host, not container-shop |
| Caddy / public reverse proxy | Tailscale-only access is the modern answer |
| Public ntfy self-host | Public ntfy.sh + random topic is enough until proven otherwise |
| jujutsu (jj) | Ecosystem (gh, Claude) still git-first; defer |

---

## Repo layout

```
fum4/devbox/                          (this repo, private)
├── README.md
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini                 # encrypted with sops, or just .gitignored
│   ├── site.yml                      # top-level playbook
│   ├── group_vars/all.yml
│   ├── roles/
│   │   ├── base/                     # apt update, base packages, fum4 user, sudoers
│   │   ├── hardening/                # disable root SSH + password auth, ufw
│   │   ├── tailscale/                # install + tailscale up --ssh (auth key from secrets)
│   │   ├── runtimes/                 # mise (it pulls node/bun/pnpm per project)
│   │   ├── agent-tools/              # ripgrep, fd, jq, gh
│   │   ├── claude/                   # Claude Code CLI via apt
│   │   ├── zellij/                   # Zellij binary
│   │   ├── claude-squad/             # Claude Squad TUI
│   │   ├── process-compose/          # binary only
│   │   ├── ntfy/                     # ntfy CLI (dormant)
│   │   └── dotfiles/                 # chezmoi apply from ../chezmoi/
│   └── secrets/
│       └── tailscale-authkey.age     # age-encrypted
└── chezmoi/
    ├── dot_bashrc                    # minimal — PATH for mise, ~/bin
    ├── dot_config/
    │   ├── zellij/config.kdl         # global zellij keybinds, theme
    │   └── mise/config.toml          # global mise defaults
    ├── private_dot_ssh/
    │   └── config.tmpl               # ssh config (templated per machine)
    └── executable_dot_local/
        └── bin/zj                    # alias-helper: zj <project> = zellij attach -c …
```

### Per-app repo additions

Each project repo (kost, future apps) carries its own:

```
<repo>/
├── .mise.toml          # tool versions + tasks + env
├── zellij.kdl          # workspace layout (tabs: shell, claude, dev server, …)
└── (optional) AGENTS.md / CLAUDE.md  # agent rules
```

No central registry. The repo is the source of truth for "how to run me."

---

## Daily workflow (target state)

### Adding a new app (~3 min after the first)

```bash
ssh vps
cd ~/code && git clone <repo>
cd <repo> && mise install
zj <project>                                 # alias: zellij attach -c <project> --layout ./zellij.kdl
# inside the claude tab: /remote-control
# → phone Claude app sees the new session
```

### Switching apps

```bash
zellij ls                                    # list active workspaces
zj kost                                      # attach
# Ctrl-o d                                   # detach
zj other-app                                 # switch
```

Or from the phone: pick the project in the Claude app.

### Rebuild VPS from scratch

```bash
# (1) Provision a new VPS via Hetzner UI (CX33, Debian 12, ssh key)
# (2) Update ansible/inventory.ini with the new IP
ansible-playbook -i ansible/inventory.ini ansible/site.yml
# ~10 minutes later, fully configured
```

---

## Phases

### Phase 0 — Validate the stack on the current VPS (~30 min)

Before turning anything into Ansible, prove the new stack works end-to-end against kost manually. Ansible should automate a recipe that's already been run by hand once.

1. Install Zellij + mise on the current VPS (apt / curl).
2. Add `zellij.kdl` to the kost repo (tabs: shell, claude, mobile, api).
3. Add `.mise.toml` to the kost repo (tasks for `mobile:dev`, `api:dev`).
4. Replace `kost-up` with `zj` alias.
5. Verify: `zj kost` brings up workspace → `claude` tab → `/remote-control` → phone Claude app shows session.
6. Verify: phone Expo Go connects to Metro over Tailscale and the kost app loads.
7. Commit `zellij.kdl` + `.mise.toml` to kost.

### Phase 1 — Write Ansible playbook + chezmoi config (~3–4 hrs)

1. Scaffold `ansible/` with the role list above.
2. Each role idempotent, ~10–30 lines of YAML.
3. Write `chezmoi/dot_bashrc` (minimal: PATH for mise, `~/bin`).
4. Write `chezmoi/dot_config/zellij/config.kdl` (global Zellij keybinds).
5. Write `chezmoi/executable_dot_local/bin/zj` (alias helper).
6. Encrypt Tailscale auth key with `age`, store in `ansible/secrets/`.
7. Test partial rollout against current VPS using tags (`ansible-playbook --tags base,hardening`).

### Phase 2 — Nuke and rebuild test (~1 hr)

The validation gate.

1. Snapshot anything important from current VPS that's not in git (probably nothing — verify).
2. Delete the VPS from Hetzner UI.
3. Create fresh VPS (CX33 / Helsinki / Debian 12).
4. Update `inventory.ini` with new IP.
5. From laptop: `ansible-playbook -i ansible/inventory.ini ansible/site.yml`.
6. Wait ~10 min.
7. `ssh vps && zj kost` → end-to-end check.

If anything is wrong, fix the playbook (Ansible is idempotent — re-run safely).

### Phase 3 — Add a second app (whenever)

1. `ssh vps; cd ~/code; git clone <repo>`
2. Add `.mise.toml` + `zellij.kdl` to the repo (commit).
3. `mise install && zj <repo>`.
4. Done.

No central change. The repo carries its own dev contract.

---

## Decisions log

Append-only. New decisions go below.

- **2026-05-18** — Phase 0 first: validate Zellij + mise on the current VPS with kost before writing Ansible. Rationale: Ansible should codify a recipe that's already been proven by hand.
- **2026-05-18** — Production deploys explicitly out of scope. kost API stays on its Fly.io CI/CD path; this box is dev-only.
- **2026-05-18** — Use one repo (`fum4/devbox`) containing both Ansible + chezmoi rather than splitting. Rationale: scale-1 user, atomic changes, no need for separate access levels.
- **2026-05-18** — Defer Codex CLI install. No Linux Remote Control as of 2026-05; re-evaluate when OpenAI ships Linux support.
- **2026-05-18** — Defer MCP server install. Add per-project when a concrete need appears (e.g. mcp-server-postgres for kost backend work).
- **2026-05-18** — Install ntfy CLI but no integrations yet. Public `ntfy.sh` + random topic when wired up.
- **2026-05-18** — Drop human-CLI-ergonomics tools (starship, atuin, zoxide, lazygit, btop, bat, eza, etc.). VPS is agent-driven; no human terminal usage to optimize.
- **2026-05-18** — Pick Ansible over Terraform. Terraform's value at scale 1 is marginal (one Hetzner API call); Ansible directly automates the painful manual runbook steps.
- **2026-05-18** — Pick Zellij over tmux. User has no tmux muscle memory to preserve; Zellij wins on declarative layouts + session resurrection + DX.

---

## References

- [Hetzner runbook (legacy, in kost repo)](../../kost/docs/runbooks/hetzner-vps-setup.md) — to migrate to this repo in Phase 1
- [mise docs](https://mise.jdx.dev)
- [Zellij docs](https://zellij.dev/documentation/)
- [chezmoi docs](https://www.chezmoi.io)
- [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control.md)
- [Claude Squad](https://github.com/smtg-ai/claude-squad)
- [ntfy.sh](https://docs.ntfy.sh)
- [Ansible docs](https://docs.ansible.com)
