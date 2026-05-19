# Provision a devbox VPS

The provisioning runbook — what you run to take a freshly-created Hetzner VPS to a fully-configured dev environment. Same procedure whether this is your **first ever** devbox or your **Nth rebuild** after destroying the previous one.

**End state**: VPS with all tools installed, GitHub identity wired, repos cloned + their deps installed, Claude session driveable from your phone.

**Time**: ~15 min walltime, ~2 min of your attention.

## Prerequisites

All set-up done once. If any are missing, do them first:

- Laptop set up per [laptop.md](laptop.md) (`secrets.local` restored, ansible/age/gh installed, SSH keys generated)
- Hetzner account ready per [hetzner.md](hetzner.md) (project + SSH key uploaded)
- Tailscale account ready per [tailscale.md](tailscale.md), with the OAuth client bootstrapped (`ansible/secrets/tailscale-oauth.age` committed)
- GitHub identity bootstrapped per [github.md](github.md) (`ansible/secrets/github-*.age` committed)

## 0. Pre-flight (optional but smart)

If you're rebuilding to replace a still-running VPS, save anything that's not in git:

```bash
ssh devbox 'for r in ~/code/*/; do [[ -d "$r/.git" ]] || continue; echo "=== $(basename $r) ==="; cd "$r"; git status -s; git log --oneline @{u}..HEAD 2>/dev/null; done'
```

Anything reported as "modified" or "unpushed" needs to be committed + pushed before you nuke the VPS, or it dies with the box.

If there's nothing surprising, proceed.

## 1. Create the VPS

Follow [hetzner.md §5 → Create a VPS](hetzner.md#5-create-a-vps). Copy the IPv4 address when it's running — step 2 needs it.

## 2. Update local config with the new IP

```bash
# Clear stale known_hosts (the old VPS's host key is invalid for the new IP)
ssh-keygen -R <NEW_IPv4>

# Update ~/.ssh/config — Host devbox HostName → new IP
$EDITOR ~/.ssh/config

# Update ansible inventory — set ansible_host + ansible_user=root for the first run
$EDITOR ~/_work/devbox/ansible/inventory.ini
```

Inventory should look like:

```ini
[devbox]
vps ansible_host=<NEW_IPv4>

[devbox:vars]
ansible_user=root
ansible_ssh_private_key_file=~/.ssh/devbox_vps
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
```

Smoke test:

```bash
ssh -i ~/.ssh/devbox_vps root@<NEW_IPv4> 'uname -a'
# Expected: Linux ... Debian 12 ...
```

## 3. Run the playbook

```bash
cd ~/_work/devbox/ansible
ansible-playbook -i inventory.ini site.yml
```

~10 minutes. What runs:

| Role | What it does |
|---|---|
| `base` | apt update, base packages, `fum4` user, sudoers, copy SSH key |
| `hardening` | disable root SSH + password auth, ufw |
| `tailscale` | install + OAuth-mint single-use key + `tailscale up --ssh` |
| `runtimes` | mise (per-project Node/Bun/pnpm) |
| `agent-tools` | ripgrep, fd, jq, gh |
| `claude` | Claude Code CLI |
| `zellij` | static binary |
| `claude-squad` | parallel-agent TUI |
| `process-compose` | binary |
| `docker` | Docker Engine + Compose plugin |
| `ntfy` | CLI (dormant) |
| `agents` | symlink `~/.agents/` → repo, install `wt prune` cron |
| `dotfiles` | chezmoi apply |
| `github-identity` | decrypt + install age-encrypted GitHub SSH key + PAT |
| `repos` | clone every repo in `repos.txt`, `mise install`, `mise run setup` |

## 4. Swap inventory to `fum4` (idempotency check)

The `base` role just created `fum4`. The `hardening` role just disabled root SSH. So the next Ansible run must come in as `fum4`:

```bash
$EDITOR inventory.ini
# Change: ansible_user=root → ansible_user=fum4
```

Re-run for idempotency:

```bash
ansible-playbook -i inventory.ini site.yml
```

Should report mostly `ok=...` with very few `changed=...`. If anything shows `changed` on this second pass, the corresponding role has a non-idempotent task — file a fix.

## 5. Claude login (interactive — only remaining one)

```bash
ssh devbox
claude
```

Inside Claude TUI:

```
/login
```

Open the printed URL on the laptop browser → sign in → click **Authorize** → copy the code → paste back at the Claude prompt → Enter.

When it confirms you're signed in:

```
/exit
```

## 6. Per-project bring-up

For each repo in `~/code/` that you'll work on actively:

```bash
zj <repo>                   # launches the project's Zellij workspace (per zellij.kdl)
```

In the Zellij session, switch to the **claude** tab (`Ctrl+T 2`). Inside Claude:

```
/remote-control
```

Choose **Enable Remote Control**. The session appears in your phone Claude app → **Code** tab.

If the project needs local infra (kost uses Docker for Postgres/Redis/MinIO):

```bash
ssh devbox
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

### Tailscale admin

https://login.tailscale.com/admin/machines → if the old VPS's node still shows (with the old IP, "expired"), delete it.

### GitHub

No action needed — the `github-identity` role uses a persistent key, so GitHub's SSH keys list doesn't accumulate stale entries on each rebuild.

### Hetzner

If you took a snapshot before destruction (for insurance), delete it now that the new VPS works: Console → Snapshots → ⋮ → Delete.

## Total interactive steps

After everything's set up:

1. Hetzner UI: create VPS (~1 min click-around)
2. Edit two files locally (inventory + ssh config + ssh-keygen -R) (~1 min)
3. `claude /login` (interactive OAuth) (~30 sec)
4. Per project: `zj <repo>` + `/remote-control` (interactive)

Everything else is one command: `ansible-playbook ...`. Tailscale auth is fully automated via the OAuth client (see [tailscale.md](tailscale.md) section 6).

## Things that go wrong (and where to look)

| Symptom | Where |
|---|---|
| `ssh root@<ip>` fails with "Permission denied" | Hetzner SSH key entry not ticked when creating VPS — recreate or attach key via UI |
| `tailscale up` fails with auth | OAuth client revoked / `tag:devbox` not in tagOwners — see [tailscale.md](tailscale.md) section 6 and [recovery.md](recovery.md) |
| `gh auth status` fails | PAT expired — rotate per [github.md](github.md) |
| `git clone` fails despite identity installed | Stale `.pub` issue or new GitHub key wasn't registered — [recovery.md](recovery.md) |
| Playbook hangs / partial fail | Re-run — Ansible is idempotent; tag the failed phase with `--tags <name>` to isolate |
| Phone Claude app shows no sessions | The VPS-side `/remote-control` got terminated — re-run inside the claude tab |

Full incident matrix in [recovery.md](recovery.md).
