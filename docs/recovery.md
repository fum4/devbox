# Recovery

What to do when things break. Organized by symptom → likely cause → fix.

If you've genuinely lost your laptop or your age key (catastrophic), start with the relevant section. Otherwise it's almost certainly fixable in 5 minutes.

## Laptop lost / replaced

You're on a new machine and need to restore everything.

1. **Set up the laptop from scratch** per [laptop.md](laptop.md) — Homebrew, age, ansible, gh, generate new SSH keys, clone the devbox repo.
2. **Register the new laptop's GitHub key** on https://github.com/settings/keys (same fum4 account as the old laptop).
3. **Restore `secrets.local`** from your password manager → place at `~/_work/devbox/secrets.local`, chmod 600.
4. **Update Hetzner** with the new laptop's `id_ed25519_devbox_hetzner.pub` → Hetzner Console → Security → SSH Keys → Add (or replace the old `laptop` entry).
5. **Update the existing VPS's `~/.ssh/authorized_keys`** so the new laptop can ssh in:
   - From any device that already has access (e.g. another laptop, or via the Hetzner Console *Rescue* mode):
     ```bash
     echo "$(cat /path/to/new-laptop-id_ed25519_devbox_hetzner.pub)" >> /home/fum4/.ssh/authorized_keys
     ```
   - If you have no way in: easier to rebuild the VPS — Hetzner UI → create a new one with the new laptop's key, then run the playbook.
6. **Delete the old laptop's keys from GitHub + Hetzner** to revoke its access.
7. **Verify**:
   ```bash
   ssh -T git@github.com    # Hi fum4!
   ssh devbox 'whoami'      # fum4
   age -d -i ~/_work/devbox/secrets.local ~/_work/devbox/ansible/secrets/github-pat.age | head -c 8
   ```

If all three pass, you're back.

## Age key lost (catastrophic)

`secrets.local` is gone AND not in any password manager. The `.age` files in the repo are unreadable.

This is recoverable but requires re-bootstrapping the GitHub identity. Steps:

1. Generate a fresh age keypair: `age-keygen -o ~/_work/devbox/secrets.local && chmod 600 ~/_work/devbox/secrets.local`. **Back up to password manager immediately.**
2. Generate a fresh GitHub SSH key (per [github.md](github.md) → bootstrap step 3).
3. Encrypt it to the new age recipient (bootstrap step 4).
4. Upload the new public key to GitHub Settings → SSH Keys (bootstrap step 5). Delete the old `devbox` entry (the private half is gone forever — useless).
5. Generate a fresh PAT (bootstrap step 6) → revoke the old PAT on Settings → Tokens.
6. Encrypt the new PAT (bootstrap step 7).
7. Commit + push the new `.age` files.
8. On every VPS still running: re-run the role to install the new identity:
   ```bash
   cd ~/_work/devbox/ansible
   ansible-playbook -i inventory.ini site.yml --tags github-identity
   ```

Nothing in the devbox is permanently lost — source code lives in git, all config lives in this repo. The recovery cost is the manual bootstrap.

## SSH to GitHub fails — `Permission denied (publickey)`

Causes ordered by likelihood:

1. **Stale `.pub` file on the VPS** — OpenSSH offers whatever public key is alongside the private. If a previous `gh auth login` left a different `.pub`, OpenSSH offers the wrong key.
   - Fix: `ssh devbox 'ssh-keygen -y -f ~/.ssh/github-fum4 > ~/.ssh/github-fum4.pub'`. Then re-run `ansible-playbook --tags github-identity` (the role does this idempotently).
2. **Public key not registered on GitHub** — check https://github.com/settings/keys. The `devbox` entry's fingerprint should match:
   ```bash
   age -d -i ~/_work/devbox/secrets.local ~/_work/devbox/ansible/secrets/github-fum4.age > /tmp/k
   chmod 600 /tmp/k && ssh-keygen -y -f /tmp/k > /tmp/k.pub
   ssh-keygen -lf /tmp/k.pub
   shred -u /tmp/k /tmp/k.pub
   ```
   If GitHub's fingerprint doesn't match, re-upload the public key.
3. **SSH config not pointing at the right key** — `cat ~/.ssh/config` should have a `Host github.com` block with `IdentityFile ~/.ssh/github-fum4`. The `github-identity` Ansible role manages this via `blockinfile`; re-run if missing.

## `gh auth status` fails

1. **PAT expired** — see [github.md](github.md) → "Rotation → PAT rotation."
2. **PAT scope changed on GitHub side** — the PAT must have `repo`, `read:org`, `workflow`. Regenerate with correct scopes.
3. **Token file deleted manually** — re-run the role:
   ```bash
   ansible-playbook -i inventory.ini site.yml --tags github-identity
   ```
   The role's `gh auth login --with-token` step will fire because `gh auth status` returns non-zero.

## `ssh devbox` fails — Permission denied / Connection refused

1. **VPS down** — Hetzner Console → check Status. Reboot if needed (⋮ → Power → Restart).
2. **IP changed** — public IP can change if the VPS was destroyed/recreated. Update `~/.ssh/config` Host devbox HostName + `inventory.ini` ansible_host.
3. **`known_hosts` mismatch** — clear stale entry: `ssh-keygen -R <ip>` and retry (accept new host key).
4. **You're trying as the wrong user** — `~/.ssh/config` should specify `User fum4`. Root SSH is disabled after the `hardening` role.
5. **Tailscale dropped on the laptop** (if you use Tailscale-routed SSH) — toggle Tailscale off and on.

## Playbook fails partway through

Ansible is idempotent — **just re-run it**. Roles that already succeeded will report `ok` and skip; the failing role will retry.

If a specific role fails repeatedly:

- **Tag-isolate**: `ansible-playbook -i inventory.ini site.yml --tags <role-name>` to focus.
- **Verbose mode**: append `-vvv` for the full stack trace from the remote.
- **Check logs**: `ssh devbox 'journalctl -e -n 50'` for systemd events; `tail -f /tmp/wt-prune.log` etc. for service-specific logs.

Common failures:

| Role | Likely cause | Fix |
|---|---|---|
| `base` | apt repo unreachable | Retry; intermittent network |
| `tailscale` | auth key invalid/expired | Generate fresh one, re-run with `TAILSCALE_AUTHKEY=tskey-... --tags tailscale` |
| `claude` | claude.ai/install.sh changed | Manually `curl claude.ai/install.sh \| bash` on the VPS; investigate |
| `repos` | github-identity didn't run / .pub stale | See above sections |
| `docker` | conflicting `docker.io` package | `sudo apt purge docker.io && sudo apt autoremove`, then re-run |

## Claude session offline on phone

1. **VPS Zellij session died** — `ssh devbox && zj <project>` to bring it back up (idempotent).
2. **Claude TUI exited inside the session** — switch to claude tab, run `claude` again, then `/remote-control`.
3. **`/remote-control` not active** — inside Claude, `/remote-control` again. Different from `/remote-control` running — must be the *Enable Remote Control* state.
4. **Anthropic relay outage** (rare) — https://status.anthropic.com.

## Metro / Expo Go can't reach Metro

1. **Tailscale off on phone** — toggle on.
2. **`REACT_NATIVE_PACKAGER_HOSTNAME` not set** — the project's `start:tailscale` task sets it. If Metro was started with plain `start`, the QR has the wrong host. Restart with `mise run mobile:dev` (which calls `start:tailscale`).
3. **VPS firewall blocking** — `ssh devbox 'sudo ufw status'` should show `tailscale0` allowed. If not, re-run `--tags hardening,tailscale`.
4. **Phone on different tailnet** — Tailscale admin console → check devices. If phone is on a different account, sign out + sign back in with the right account.

## Docker fails — "permission denied"

The user `fum4` must be in the `docker` group. The `docker` Ansible role adds this, but **group membership only takes effect on new shells**.

- If you opened a Zellij session BEFORE the role ran, that session's panes don't have docker group → `docker` commands fail.
- Fix: `exit` the Zellij session (`Ctrl+O d` to detach is not enough — actually exit each shell), reconnect (`ssh devbox`), `zj <project>` fresh. New shells pick up the group.
- Workaround if you don't want to restart shells: `newgrp docker` in the current shell, then docker works (only for that shell).

## Whole-VPS rebuild from a degraded state

If something on the VPS is so broken you can't easily fix it: **rebuild**. The runbook in [provisioning.md](provisioning.md) takes ~15 min. Nothing on the VPS is irreplaceable:

- Code: in git
- Tool versions / dependencies: re-installed by the playbook + `mise install` + `mise run setup`
- Dotfiles: in `chezmoi/`
- AGENTS.md + skills: symlinked from the devbox checkout
- The few one-time things (claude /login, per-project /remote-control) are short interactive steps

If in doubt, nuke + rebuild beats debugging.

## What to do BEFORE asking for help

When something breaks and you want to ask the agent (or a human) for help:

1. **Reproduce the error** — copy the exact command + the exact error message
2. **Check the obvious**: connectivity (Tailscale on?), auth (gh auth status?), runtime (mise install run?)
3. **Try the most-broken-state remedy**: re-run the relevant role with `--tags <name>`. Ansible is idempotent — re-running rarely hurts.
4. **Capture logs**: `journalctl -e -n 100`, `tail /tmp/wt-prune.log`, `mise tasks` output, etc.

With those four in hand, the cause is usually obvious from the symptom matrix above.
