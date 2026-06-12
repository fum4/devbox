# Provision a devbox VPS

The provisioning runbook — what you run to take a freshly-created Hetzner VPS to a fully-configured dev environment. Same procedure whether this is your **first ever** devbox or your **Nth rebuild** after destroying the previous one.

**End state**: VPS with all tools installed, GitHub identity wired, repos cloned + their deps installed, Claude session driveable from your phone.

**Time**: ~15 min walltime, ~2 min of your attention.

## Where each command runs

Three contexts appear in this doc; every code block is labeled with one of them.

- **On the laptop** — your Mac. The devbox repo is at `~/_work/devbox`. Ansible runs from here.
- **On the VPS** — after `ssh devbox`. The devbox repo is at `~/code/devbox`. Linux.
- **Inside the Claude TUI** — the `claude` REPL running inside a VPS shell. Slash-commands (`/login`, `/remote-control`, …), not bash.

## Prerequisites

All set-up done once. If any are missing, do them first:

- Laptop set up per [laptop.md](laptop.md) (`secrets.local` restored, ansible/age/gh installed, SSH keys generated)
- Hetzner account ready per [hetzner.md](hetzner.md) (project + API token), Terraform bootstrapped per [terraform.md](terraform.md) (R2 state bucket + lane-2 creds restored)
- Tailscale account ready per [tailscale.md](tailscale.md), with the OAuth client bootstrapped (`ansible/secrets/tailscale-oauth.age` committed)
- GitHub identity bootstrapped per [github.md](github.md) (`ansible/secrets/github-*.age` committed)

## 0. Pre-flight (optional but smart)

If you're rebuilding to replace a still-running VPS, save anything that's not in git.

**On the laptop** (executes the quoted command on the VPS via one-shot SSH):

```bash
ssh devbox 'for r in ~/code/*/; do [[ -d "$r/.git" ]] || continue; echo "=== $(basename $r) ==="; cd "$r"; git status -s; git log --oneline @{u}..HEAD 2>/dev/null; done'
```

Anything reported as "modified" or "unpushed" needs to be committed + pushed before you nuke the VPS, or it dies with the box.

If there's nothing surprising, proceed.

### Rebuilds are sequential (one IP, one box)

The box's IPv4 is a **stable primary IP** that moves from the old server to the new one ([terraform.md](terraform.md)) — which means old and new **can't run side by side**. The rebuild order is: destroy old → apply new (same IP). Your safety nets are §0's WIP sweep (everything durable is in git / `*.age` / R2 anyway) and, if you want belt-and-braces, a Hetzner snapshot right before destroying (Console → server → ⋮ → Snapshot; delete it in §8 once the new box works).

## 1. Recreate the VPS (Terraform)

**On the laptop:**

```bash
cd ~/_work/devbox
bin/devbox-tf destroy -target=hcloud_server.devbox   # rebuild only: removes the old box; the IP survives
bin/devbox-tf apply                                  # new Debian 12 box, SAME IPv4
```

First-ever setup (no box yet, no creds yet): do the one-time bootstrap in [terraform.md](terraform.md) first, then just `bin/devbox-tf apply`.

## 2. Reset the host key (the IP didn't change)

`~/.ssh/config` and `ansible/inventory.ini` already point at the right IP — the primary IP survived the rebuild, so there's nothing to update. (First-ever setup only: put the `apply` output's IP into both, once; the inventory shape is in `ansible/inventory.ini.example`.) Two things remain:

**On the laptop:**

```bash
# A new box has a new HOST KEY even on the old IP — clear the stale entry
ssh-keygen -R <IPv4>

# Ansible must come in as root for the first run (base creates fum4, hardening locks root)
$EDITOR ~/_work/devbox/ansible/inventory.ini    # ansible_user=root
```

Smoke test, **on the laptop** (the `uname -a` itself executes on the VPS but `ssh` is initiated from here):

```bash
ssh -i ~/.ssh/devbox_vps root@<IPv4> 'uname -a'
# Expected: Linux ... Debian 12 ...
```

## 3. Run the playbook

**On the laptop** (Ansible runs here and configures the VPS over SSH):

```bash
cd ~/_work/devbox/ansible
ansible-playbook -i inventory.ini site.yml
```

~10 minutes. What runs:

| Role | What it does |
|---|---|
| `base` | apt update, base packages, `fum4` user, sudoers, copy SSH key |
| `hardening` | disable root SSH + password auth, ufw |
| `swap` | 2G swapfile + `vm.swappiness=10` (safety mat for cgroup `MemoryHigh` throttling) |
| `tailscale` | install + OAuth-mint single-use key + `tailscale up --ssh` |
| `runtimes` | mise (per-project Node/Bun/pnpm) |
| `agent-tools` | ripgrep, fd, jq, gh |
| `claude` | Claude Code CLI |
| `zellij` | static binary |
| `claude-squad` | parallel-agent TUI |
| `process-compose` | binary |
| `docker` | Docker Engine + Compose plugin |
| `playwright-deps` | apt libs for Chromium headless-shell (kost `tools/preview/`, future e2e) |
| `ntfy` | CLI (dormant) |
| `agents` | symlink `~/.agents/` → repo |
| `dotfiles` | chezmoi apply |
| `github-identity` | decrypt + install age-encrypted GitHub SSH key + PAT |
| `repos` | clone every repo in `repos.txt`, `mise install`, `mise run setup` |

## 4. Swap inventory to `fum4` (idempotency check)

The `base` role just created `fum4`. The `hardening` role just disabled root SSH. So the next Ansible run must come in as `fum4`.

**On the laptop:**

```bash
$EDITOR inventory.ini
# Change: ansible_user=root → ansible_user=fum4
```

Re-run for idempotency, **on the laptop:**

```bash
ansible-playbook -i inventory.ini site.yml
```

Should report mostly `ok=...` with very few `changed=...`. If anything shows `changed` on this second pass, the corresponding role has a non-idempotent task — file a fix.

## 5. Claude login (interactive — only remaining one)

**On the laptop**, open a shell on the VPS:

```bash
ssh devbox
```

**On the VPS** (the line above put you there), launch Claude:

```bash
claude
```

**Inside the Claude TUI:**

```
/login
```

Open the printed URL **in your laptop browser** → sign in → click **Authorize** → copy the code → paste it at the Claude prompt → Enter.

When it confirms you're signed in, **inside the Claude TUI:**

```
/exit
```

## 6. Per-project bring-up

For each repo in `~/code/` (the VPS path) that you'll work on actively, **on the VPS** (still ssh'd from step 5, or `ssh devbox` again):

```bash
zj <repo>                   # launches the project's Zellij workspace (per zellij.kdl)
```

In the Zellij session, switch to the **claude** tab (`Ctrl+T 2`). Claude is auto-launched there.

**Inside the Claude TUI:**

```
/remote-control
```

Choose **Enable Remote Control**. The session appears in your phone Claude app → **Code** tab.

If the project needs local infra (kost uses Docker for Postgres/Redis/MinIO):

**On the laptop:**

```bash
ssh devbox
```

**On the VPS:**

```bash
zj kost
# Ctrl+T 1 (shell tab)
mise run infra:up         # if defined; otherwise pnpm dev:infra or docker compose up -d
# Ctrl+T 4 (api tab or similar)
mise run api:dev
```

## 7. Phone verification

Open Claude app on the phone:

- **Code tab** shows the session(s) you `/remote-control`'d. Green dot = live.
- Tap one → prompt the agent ("show me CLAUDE.md") → response renders inline.

For Expo Go testing (mobile apps): see [mobile.md](mobile.md) step 3.

## 8. Cleanup

### The old VPS (rebuilds only)

Nothing to do — §1's `destroy -target` already removed it (rebuilds are sequential now; see §0). If `bin/devbox-tf plan` reports anything unexpected, reconcile before walking away.

### Tailscale admin

https://login.tailscale.com/admin/machines → if the old VPS's node still shows (with the old IP, "expired"), delete it.

### GitHub

No action needed — the `github-identity` role uses a persistent key, so GitHub's SSH keys list doesn't accumulate stale entries on each rebuild.

### Hetzner snapshots

If you took a snapshot before destruction (for insurance), delete it now that the new VPS works: Console → Snapshots → ⋮ → Delete.

## Total interactive steps

After everything's set up:

1. `bin/devbox-tf destroy -target=… && bin/devbox-tf apply` (~1 min, mostly waiting)
2. `ssh-keygen -R <ip>` + flip inventory to `ansible_user=root` (~30 sec)
3. `claude /login` (interactive OAuth) (~30 sec)
4. Per project: `zj <repo>` + `/remote-control` (interactive)

Everything else is one command: `ansible-playbook ...`. Tailscale auth is fully automated via the OAuth client (see [tailscale.md](tailscale.md) section 6); the IP never changes, so no config files to touch.

## Things that go wrong (and where to look)

| Symptom | Where |
|---|---|
| `ssh root@<ip>` fails with "Permission denied" | The `hcloud_ssh_key` didn't match your laptop key — check `terraform/devbox/variables.tf` `ssh_public_key_path` and re-apply ([terraform.md](terraform.md)) |
| `bin/devbox-tf` fails (creds, state, 401) | [terraform.md](terraform.md) → "Things that go wrong" |
| `tailscale up` fails with auth | OAuth client revoked / `tag:devbox` not in tagOwners — see [tailscale.md](tailscale.md) section 6 and [recovery.md](recovery.md) |
| `gh auth status` fails | PAT expired — rotate per [github.md](github.md) |
| `git clone` fails despite identity installed | Stale `.pub` issue or new GitHub key wasn't registered — [recovery.md](recovery.md) |
| Playbook hangs / partial fail | Re-run — Ansible is idempotent; tag the failed phase with `--tags <name>` to isolate |
| Phone Claude app shows no sessions | The VPS-side `/remote-control` got terminated — re-run inside the claude tab |

Full incident matrix in [recovery.md](recovery.md).
