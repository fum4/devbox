# ansible/

Provisioning layer: turns a freshly created Debian 12 VPS into a fully configured dev box. Idempotent — re-running is safe and incremental.

## What it does, end-to-end

Each role does one concern. Roles run in the order in `site.yml`:

| # | Role | What it does | Why this order |
|---|---|---|---|
| 1 | `base` | apt upgrade, install base packages, create `fum4` user, sudoers, copy SSH key | Must come first — creates the user later roles run as |
| 2 | `hardening` | Disable root SSH + password auth, ufw default-deny | Right after `base`: lock down the box before installing anything else |
| 3 | `tailscale` | Install Tailscale, allow `tailscale0` in ufw, OAuth-mint a single-use auth key + `tailscale up --ssh` | Needed before exposing dev servers (Metro etc.) over the tailnet |
| 4 | `runtimes` | Install **mise** (per-project Node/Bun/pnpm + tasks + env) | Foundation for per-project dev environments |
| 5 | `agent-tools` | Install ripgrep, fd, jq, gh | Tools the agent shells out to — not human ergonomics |
| 6 | `claude` | Install Claude Code CLI via the official apt repo | Needs the user (base) and Tailscale (for `/remote-control`) up |
| 7 | `zellij` | Install Zellij static binary | Workspace layer — used by `zj` to attach to project sessions |
| 8 | `claude-squad` | Install Claude Squad (parallel-agent TUI) | Optional, but cheap; here so it's always available |
| 9 | `process-compose` | Install the binary (no services configured yet) | Available for headless service stacks (DB/Redis) when needed |
| 10 | `docker` | Install Docker Engine + Compose plugin | Local infra stacks (Postgres/Redis/MinIO for projects); per-repo `compose.yml` brings them up |
| 11 | `ntfy` | Install the ntfy CLI binary | Installed dormant — no topics or systemd subscriptions wired up |
| 12 | `github-identity` | Decrypt age-encrypted GitHub SSH key + PAT (`secrets/github-*.age`), install on VPS, `gh auth login --with-token` | Bootstrap once per laptop (see `docs/github.md`); skipped silently if secrets absent. Runs before `repos` so SSH-cloning works. |
| 13 | `repos` | Clone every line of `repos.txt` to `~/code/<basename>`, then `mise install` + `mise run setup` per repo | Includes the devbox repo itself, so `~/code/devbox/` is on disk before `agents` symlinks at it. |
| 14 | `agents` | Symlink `~/.agents/{AGENTS.md,README.md,skills}` → `~/code/devbox/agents/`, then point `~/.claude/` + `~/.codex/` agent paths at `~/.agents/`; install the `wt prune` cron | Must run *after* `repos` — symlink targets are paths inside the devbox checkout. |
| 15 | `dotfiles` | Install chezmoi, `chezmoi init --apply --source=../chezmoi` | Needs the user, mise activated, all tools in place |

## Prerequisites

- **Ansible** ≥ 2.16 on your laptop (`brew install ansible` on macOS).
- **`age`** on your laptop (`brew install age`) — used by the controller to decrypt `secrets/*.age` at playbook runtime.
- **SSH access** to the VPS, key-based. Your `~/.ssh/config` should have a `Host devbox` entry pointing at the VPS's public IPv4 with the right private key. (The root README's "First-time setup" covers this.)
- **`secrets.local`** at the repo root (the age private key, restored from your password manager). This decrypts:
  - `secrets/tailscale-oauth.age` — OAuth client_secret for unattended Tailscale auth (see [`docs/tailscale.md`](../docs/tailscale.md) §6 for the one-time bootstrap)
  - `secrets/github-ssh.age` + `secrets/github-pat.age` — GitHub identity (see [`docs/github.md`](../docs/github.md))
- (legacy fallback) **`TAILSCALE_AUTHKEY` env var** — only used when `secrets/tailscale-oauth.age` doesn't exist yet. Generate a one-shot key at https://login.tailscale.com/admin/settings/keys.

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
ansible-playbook -i inventory.ini site.yml
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

The age-encryption pattern (threat model, encrypt/decrypt recipes, the four-directive Ansible template, new-laptop recovery) is fully documented in [`../docs/secrets.md`](../docs/secrets.md). Read that doc before adding new secrets — it's the authoritative reference.

Three secrets currently live this way:

| File | Decrypts to | Used by |
|---|---|---|
| `secrets/tailscale-oauth.age` | OAuth client_secret (`tskey-client-…`) | `tailscale` role — exchanges for an access token, mints a fresh single-use auth key per provision |
| `secrets/github-ssh.age` | An SSH private key | `github-identity` role — installed at `~/.ssh/github-ssh` on the VPS |
| `secrets/github-pat.age` | A GitHub PAT (`ghp_…`) | `github-identity` role — fed to `gh auth login --with-token` |

All three are decrypted **on the controller** (your laptop) via `delegate_to: localhost` and `no_log: true`. The plaintext never lands on disk on the VPS — it's pushed in over SSH and either piped into a command or written directly to the destination file in-memory.

The `TAILSCALE_AUTHKEY` env var is the legacy fallback path; the OAuth flow replaces it once `tailscale-oauth.age` is bootstrapped.

### Add a new host (second VPS)

Add it to `inventory.ini`:

```ini
[devbox]
vps ansible_host=46.62.x.x
staging ansible_host=49.13.y.y

[devbox:vars]
ansible_user=fum4
ansible_ssh_private_key_file=~/.ssh/devbox_vps
```

Run as before — Ansible applies to all hosts in the group. Use `-l <host>` to target one.

## Troubleshooting

**`Permission denied (publickey)` on first run**
- The Hetzner SSH-key entry doesn't match your local key, or wasn't ticked when you created the VM. Recreate the VM (billing is hourly), or fix the public key in Hetzner's UI and click "rebuild image."

**`Authentication failed` on tailscale `up`**
- OAuth path: the role's `Exchange OAuth credentials for an access token` or `Mint a fresh single-use Tailscale auth key via API` step likely returned 4xx. See [`docs/recovery.md`](../docs/recovery.md) → "Tailscale OAuth failures" for the per-task matrix (revoked client, missing scope, `tag:devbox` not in tagOwners).
- Fallback path: `TAILSCALE_AUTHKEY` is empty or expired. Generate a fresh one at https://login.tailscale.com/admin/settings/keys, or run `sudo tailscale up --ssh` manually after the playbook.

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
