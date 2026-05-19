# ansible/

Provisioning layer: turns a freshly created Debian 12 VPS into a fully configured dev box. Idempotent — re-running is safe and incremental.

## What it does, end-to-end

Each role does one concern. Roles run in the order in `site.yml`:

| # | Role | What it does | Why this order |
|---|---|---|---|
| 1 | `base` | apt upgrade, install base packages, create `fum4` user, sudoers, copy SSH key | Must come first — creates the user later roles run as |
| 2 | `hardening` | Disable root SSH + password auth, ufw default-deny | Right after `base`: lock down the box before installing anything else |
| 3 | `tailscale` | Install Tailscale, allow `tailscale0` in ufw, `tailscale up --ssh` | Needed before exposing dev servers (Metro etc.) over the tailnet |
| 4 | `runtimes` | Install **mise** (per-project Node/Bun/pnpm + tasks + env) | Foundation for per-project dev environments |
| 5 | `agent-tools` | Install ripgrep, fd, jq, gh | Tools the agent shells out to — not human ergonomics |
| 6 | `claude` | Install Claude Code CLI via the official apt repo | Needs the user (base) and Tailscale (for `/remote-control`) up |
| 7 | `zellij` | Install Zellij static binary | Workspace layer — used by `zj` to attach to project sessions |
| 8 | `claude-squad` | Install Claude Squad (parallel-agent TUI) | Optional, but cheap; here so it's always available |
| 9 | `process-compose` | Install the binary (no services configured yet) | Available for headless service stacks (DB/Redis) when needed |
| 10 | `docker` | Install Docker Engine + Compose plugin | Local infra stacks (Postgres/Redis/MinIO for projects); per-repo `compose.yml` brings them up |
| 11 | `ntfy` | Install the ntfy CLI binary | Installed dormant — no topics or systemd subscriptions wired up |
| 12 | `agents` | Symlink `~/.agents/{AGENTS.md,README.md,skills}` → `~/code/devbox/agents/`, then point `~/.claude/` + `~/.codex/` agent paths at `~/.agents/`; install the `wt prune` cron | Needs the user (base) and a checkout of this repo on the VPS |
| 13 | `dotfiles` | Install chezmoi, `chezmoi init --apply --source=../chezmoi` | Last — needs the user, mise activated, all tools in place |

## Prerequisites

- **Ansible** ≥ 2.16 on your laptop (`brew install ansible` on macOS).
- **SSH access** to the VPS, key-based. Your `~/.ssh/config` should have a `Host devbox` entry pointing at the VPS's public IPv4 with the right private key. (The root README's "First-time setup" covers this.)
- **Tailscale auth key** if you want the playbook to authenticate the box without a browser visit. Get one at https://login.tailscale.com/admin/settings/keys (pre-authorized, reusable=no, expiry=24h is fine). Pass via the `TAILSCALE_AUTHKEY` env var; the playbook picks it up via `group_vars/all.yml`.

## File layout

```
ansible/
├── ansible.cfg                  Ansible defaults: inventory path, role path,
│                                stdout=yaml, pipelining, persistent SSH sockets.
├── inventory.ini.example        Template — copy to inventory.ini, edit IPs.
├── inventory.ini                Real inventory (gitignored).
├── group_vars/
│   └── all.yml                  Shared vars: username, Tailscale key lookup,
│                                Node version floor.
├── site.yml                     Top-level playbook. Defines the role order and
│                                tags for partial runs.
├── secrets/                     age-encrypted material lives here (gitignored
│                                except .age files).
│   └── .gitkeep
└── roles/                       One folder per role.
    ├── <role>/
    │   ├── tasks/main.yml       The actual steps.
    │   ├── handlers/main.yml    (optional) reaction tasks, e.g. restart sshd.
    │   └── defaults/main.yml    (optional) role-default variables.
    └── …
```

## Running the playbook

### First time (against a fresh VPS)

```bash
# Real inventory from template
cp inventory.ini.example inventory.ini
# Edit inventory.ini → set the new VPS's public IP

# Run as root (Hetzner's default for freshly created VPSes)
TAILSCALE_AUTHKEY=tskey-... ansible-playbook -i inventory.ini site.yml
```

The `base` role creates the `fum4` user with your SSH key. After the playbook completes:

```bash
# Edit inventory.ini → change ansible_user=root to ansible_user=fum4
# Re-run as fum4 to confirm idempotency
ansible-playbook -i inventory.ini site.yml
```

The second run should be entirely "ok" (no changed tasks) — that's the idempotency signal.

### Subsequent runs

After the first time, the inventory should already point to `fum4`. Just:

```bash
ansible-playbook -i inventory.ini site.yml
```

### Partial runs via tags

`site.yml` tags every role. Run only the parts you care about:

```bash
# Just update Claude / Zellij / Claude Squad
ansible-playbook -i inventory.ini site.yml --tags tools

# Just re-apply dotfiles after editing chezmoi/
ansible-playbook -i inventory.ini site.yml --tags dotfiles

# Skip the slow tools install when iterating on configuration
ansible-playbook -i inventory.ini site.yml --skip-tags tools
```

Tags currently defined:
- `bootstrap` — base, hardening, tailscale (the "boot from nothing" subset)
- `tools` — runtimes, agent-tools, claude, zellij, claude-squad, process-compose, docker, ntfy
- `dotfiles` — agents + chezmoi apply
- One tag per role (e.g. `--tags claude`)

### Dry-run

```bash
ansible-playbook -i inventory.ini site.yml --check --diff
```

`--check` reports what would change without changing anything. `--diff` shows file content changes. Combined: a safe preview.

## How to extend

### Add a new role

```bash
mkdir -p ansible/roles/<name>/tasks
cat > ansible/roles/<name>/tasks/main.yml <<EOF
---
- name: ...
  apt:
    name: ...
    state: present
EOF
```

Then add it to `site.yml`:

```yaml
- role: <name>
  tags: [<name>, tools]   # or whatever group fits
```

### Add a secret

`ansible/secrets/` is gitignored except `*.age` files. Workflow:

```bash
echo "my-secret" > secrets/foo.txt
age -e -r <your-pubkey> secrets/foo.txt > secrets/foo.age
rm secrets/foo.txt
# Commit foo.age (encrypted)
```

In a role, decrypt at runtime via `lookup('pipe', 'age -d -i <keyfile> secrets/foo.age')` or via `community.sops` if you switch to sops.

For now we use environment variables for the one secret we need (`TAILSCALE_AUTHKEY`).

### Add a new host (second VPS)

Add it to `inventory.ini`:

```ini
[devbox]
vps ansible_host=46.62.x.x
staging ansible_host=49.13.y.y

[devbox:vars]
ansible_user=fum4
ansible_ssh_private_key_file=~/.ssh/id_ed25519_devbox_hetzner
```

Run as before — Ansible applies to all hosts in the group. Use `-l <host>` to target one.

## Troubleshooting

**`Permission denied (publickey)` on first run**
- The Hetzner SSH-key entry doesn't match your local key, or wasn't ticked when you created the VM. Recreate the VM (billing is hourly), or fix the public key in Hetzner's UI and click "rebuild image."

**`Authentication failed` on tailscale `up`**
- `TAILSCALE_AUTHKEY` is empty or expired. Generate a fresh one. Or comment out the `tailscale_auth_key` task and run `sudo tailscale up --ssh` manually after the playbook.

**Re-run says "module command had errors but RC=0"**
- Usually a shell module without `creates:` running the same install twice. Add `creates: <path>` to make it idempotent.

**A role hangs forever**
- Often a `command` task is interactive (waits for stdin). Wrap with `become_user`, redirect stdin from `/dev/null`, or break it into smaller idempotent steps.

**`Could not match supplied host pattern: devbox`**
- `inventory.ini` is missing or the group is named differently. Check `[devbox]` header.

## Conventions

- One concern per role. If a role is doing two unrelated things, split it.
- Every task has a human-readable `name:` (shows up in the playbook log).
- Prefer idempotent modules (`apt`, `lineinfile`, `ufw`) over `command`/`shell`.
- When you have to use `command`/`shell`, add `args.creates:` so re-runs are no-ops.
- Variables go in `group_vars/all.yml` or role defaults — never inline in tasks.
- Restart-only-when-needed: use **handlers** for actions like restarting sshd.
