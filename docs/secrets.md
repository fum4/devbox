# Encrypted secrets

How the devbox stores secrets next to its code without leaking them, and what to do when you set up on a new laptop.

> Sister docs: [`laptop.md`](laptop.md) (overall laptop bootstrap), [`github.md`](github.md) (the GitHub identity that uses this pattern), [`tailscale.md`](tailscale.md) §6 (the Tailscale OAuth client that uses this pattern), [`recovery.md`](recovery.md) (incident response).

> All commands in this doc run **on the laptop**. The age private key (`secrets.local`) lives there exclusively — decryption never happens on the VPS.

## The pattern in one paragraph

We use `age` (a small public-key encryption tool) with a single keypair. The **public key** lives in plaintext at the top of `secrets.local` and is the *recipient* of every encrypted file. The **private key** lives in the same file and is the *only* thing that can decrypt those files. We commit the `*.age` files to the repo; `secrets.local` itself is gitignored and backed up to your password manager. Ansible decrypts secrets on the **controller** (your laptop) at playbook runtime, holds the plaintext in memory, and either consumes it directly (e.g. POST to an API) or pushes it over SSH to the VPS. The VPS never has the age private key.

## Threat model

| Attacker has | Can they decrypt? | What they get |
|---|---|---|
| The repo (clone of GitHub, mirror, anyone with access) | No | Encrypted blobs, useless without `secrets.local` |
| Your laptop, FileVault unlocked | Yes — fully | Both `secrets.local` and the repo |
| Your laptop, FileVault locked | No | Disk is encrypted at rest |
| Root on the VPS | Partial | Plaintext GitHub SSH key + PAT + active Tailscale session at rest. **No** Tailscale OAuth `client_secret` (never pushed to the VPS) |
| `secrets.local` alone | No | The key fits no lock they have |
| GitHub account compromise | No | Same as "the repo" |

The single point of total failure is "laptop + FileVault unlocked." That's why FileVault is mandatory and `secrets.local` lives in your password manager as the recovery path.

## Restoring on a new laptop

You've followed [`laptop.md`](laptop.md) up to step 8 — the repo is cloned but `secrets.local` is missing, so `*.age` files can't be decrypted yet.

1. Open your password manager → find the entry named something like *"devbox age private key"*.
2. The entry should look like:
   ```
   # created: 2026-05-20T...
   # public key: age1xxxxxxxxxxxxxxxxxxxxxxxx
   AGE-SECRET-KEY-1xxxxxxxxxxxxxxxxxxxxxxxx
   ```
3. Restore it to the repo root:
   ```bash
   cd ~/_work/devbox
   pbpaste > secrets.local
   chmod 600 secrets.local
   ```
4. Verify the whole secret store decrypts:
   ```bash
   for f in ansible/secrets/*.age; do
     printf '%-40s ' "$f:"
     age -d -i secrets.local "$f" 2>&1 | head -c 12
     echo
   done
   ```
   Expected output (something like):
   ```
   ansible/secrets/github-ssh.age:        -----BEGIN OP
   ansible/secrets/github-pat.age:         ghp_xxxxxxxx
   ansible/secrets/tailscale-oauth.age:    tskey-client
   ```
5. If any file fails with `no identity matched any recipient`, the age key in your password manager doesn't match the public key those files were encrypted to. That means either:
   - You restored the wrong age key — check the password manager for another entry.
   - The encrypted files were re-keyed (e.g. someone rotated the age keypair) and your password manager copy is stale. Recover via [`recovery.md`](recovery.md) → "Age key lost (catastrophic)".

If all three decrypt cleanly, you're done — laptop is ready to run Ansible.

## Inventory of current secrets

| File | Plaintext | Consumed by | Plaintext reaches VPS? |
|---|---|---|---|
| `ansible/secrets/github-ssh.age` | OpenSSH ed25519 private key | `github-identity` role → `~/.ssh/github-ssh` on VPS | Yes (the VPS needs to use the key for git ops) |
| `ansible/secrets/github-pat.age` | GitHub PAT (`ghp_…`) | `github-identity` role → piped into `gh auth login --with-token` | Yes (stored at `~/.config/gh/hosts.yml`) |
| `ansible/secrets/tailscale-oauth.age` | Tailscale OAuth `client_secret` (`tskey-client-…`) | `tailscale` role → exchanged for an access token, used to mint a single-use auth key | **No** — only the minted key reaches the VPS |
| `ansible/secrets/expo-kost.age` | EAS access token (`EXPO_TOKEN`, robot `kost-eas`) | `expo-identity` role → `export EXPO_TOKEN=…` in `~/.bashrc.local`. CI reads its own GitHub Actions secret, synced from this token (`gh secret set`). See [`expo.md`](expo.md). | Yes (at rest in `~/.bashrc.local`, mode 0600) |

Why four secrets, two patterns: the OAuth `client_secret` is more powerful than the keys it mints, so we keep it on the controller. The GitHub PAT and SSH key are what the VPS actually needs in operation, so they have to live there. See [the PAT/OAuth explainer](#why-the-different-shapes) below.

## Adding a new encrypted secret

The pattern, in three lines:

```bash
cd ~/_work/devbox
AGE_PUB=$(grep -o 'age1[0-9a-z]*' secrets.local | head -1)
echo -n "the-secret-value" | age -r "$AGE_PUB" -o ansible/secrets/<name>.age
git add ansible/secrets/<name>.age && git commit -m "chore(secrets): add <name>"
```

For multi-line secrets (e.g. an SSH private key), encrypt from a file instead:

```bash
age -r "$AGE_PUB" -o ansible/secrets/<name>.age /path/to/plaintext
shred -u /path/to/plaintext 2>/dev/null || rm /path/to/plaintext
```

Then in the consuming Ansible role, follow this template:

```yaml
- name: Decrypt <name> on the controller
  command: age -d -i {{ playbook_dir }}/../secrets.local {{ playbook_dir }}/secrets/<name>.age
  register: my_secret
  delegate_to: localhost   # decrypt on the laptop, not the VPS
  become: false            # secrets.local is mode 0600, owned by you
  no_log: true             # don't dump plaintext into Ansible logs
  changed_when: false

- name: Use the decrypted secret
  uri:                     # or `copy:`, or `command:`, etc.
    url: https://api.example.com/endpoint
    headers:
      Authorization: "Bearer {{ my_secret.stdout }}"
  no_log: true
```

The four directives that matter:

| Directive | What it gives you |
|---|---|
| `delegate_to: localhost` | The decryption runs on your laptop. The VPS never needs (or sees) the age private key. |
| `become: false` | No sudo elevation; `secrets.local` is owned by you in mode 0600. |
| `no_log: true` | Suppresses Ansible's stdout/log capture. Without this, `-vvv` would dump plaintext to your terminal and into any CI artifact. |
| `register: my_secret` | Plaintext lives only in an Ansible variable in memory, never on disk. |

The `.gitignore` already whitelists `ansible/secrets/*.age`, so the encrypted file commits but plaintext drops never do.

## Project secrets — enrolling a repo

The store above holds the *devbox's own* identity secrets, but the rule is
universal (and codified in `agents/AGENTS.md`): **no secret on this box may exist
only as gitignored plaintext in a repo's working tree.** That plaintext dies on a
rebuild and vanishes if the laptop is lost — the same drift trap as a hand-edited
live config. Every project that accumulates secrets enrolls them here instead, so
the one root of trust (your age key, in the password manager) recovers everything.

The pattern, mirroring `github-identity` / `expo-identity`:

1. Encrypt each secret as `ansible/secrets/<repo>-<name>.age` (see *Adding a new
   encrypted secret* above).
2. Write a per-repo role (`<repo>-secrets` / `<repo>-identity`) that decrypts on
   the laptop (`delegate_to: localhost`, `no_log: true`) and **places the
   gitignored files** the repo's dev/deploy contract expects — `.env`s, tfvars,
   SSH keys — onto the box, the way `github-identity` writes `~/.ssh/github-ssh`.
3. Add the role to the play and a row to the inventory table above.

The payoff: those files stop being hand-crafted load-bearing state. A rebuilt
devbox regenerates them from the encrypted source on provision; a lost laptop is
recovered by restoring the age key from the password manager.

> **Foundation (independent of any repo):** the password manager must hold the
> **age private key** *and* the **provider account logins + 2FA recovery codes**
> (Cloudflare, Hetzner, Vercel, Clerk, OpenRouter, GitHub, …). Those account
> logins are the true root — regenerating any token assumes you can still log in.

### Pending: kost infra secrets

kost's bootstrap secrets currently live only as gitignored plaintext on the
devbox — the first repo to enroll. Decision + rationale recorded 2026-06-10
(chosen over SOPS-in-repo and a managed secret manager: both duplicate or
over-build vs this age store). kost's app *runtime* secrets are already durable
(Coolify's encrypted DB + the nightly R2 backup bundle that carries `APP_KEY`),
so only the **infra set** is the gap:

| To encrypt → `ansible/secrets/` | Plaintext | Role places it at |
|---|---|---|
| `kost-hcloud-token.age` | Hetzner API token | `~/code/kost/infra/terraform/terraform.tfvars` |
| `kost-vercel-token.age` | Vercel API token | ↑ same tfvars |
| `kost-r2-backup.age` | R2 `kost-backup` key id + secret | tfvars **and** `infra/terraform/.r2-backend.env` |
| `kost-vps-ssh.age` | `kost_vps` private key | `~/.ssh/kost_vps` (mode 0600) |
| `kost-coolify-appkey.age` | Coolify `APP_KEY` (recovery copy) | — (recovery only; Coolify stays the runtime source) |

Open choices for the implementing session: role name (`kost-secrets` vs
`kost-identity`); whether to also enroll the dev env files (`apps/api/.env`,
`apps/mobile/.env.local`) so a fresh box can `mise run dev`, not just deploy (also
retires the per-worktree env-copy chore); and a re-encrypt step in kost's token-
rotation runbook so `kost-coolify-appkey.age` can't drift. kost-side context:
`~/code/kost/docs/runbooks/disaster-recovery.md`.

## Decrypting for verification or debugging

Sometimes you just want to read a secret (rotate it, debug, sanity-check that the right value is in there).

```bash
cd ~/_work/devbox

# Decrypt to stdout
age -d -i secrets.local ansible/secrets/github-pat.age

# Just check the first bytes (safer for screen-sharing)
age -d -i secrets.local ansible/secrets/github-pat.age | head -c 8
# ghp_xxxx

# Decrypt to a temp file and shred it after
age -d -i secrets.local ansible/secrets/github-ssh.age > /tmp/k
# ...use /tmp/k...
shred -u /tmp/k 2>/dev/null || rm /tmp/k
```

Never pipe a decrypted secret somewhere persistent without shredding it after. The dangerous shapes are:
- Redirecting into a file in the repo (`> some-file`) → committed by accident
- Echoing in a chat / Slack / screenshot
- Writing it to `~/.bash_history` (use `set +o history` for the command, or `printf` instead of `echo` for secrets)

## Why the different shapes (PAT vs OAuth)

GitHub and Tailscale offer different machine-credential shapes:

| | GitHub | Tailscale |
|---|---|---|
| Machine credential type | PAT (long-lived bearer token) | OAuth client (client_id + client_secret) |
| What we store encrypted | The PAT itself | client_id (public, plaintext) + client_secret (encrypted) |
| What the VPS receives | The PAT (used directly) | A minted single-use auth key (10-min expiry, scoped to `tag:devbox`) |
| Lifetime model | Long-lived secret, used directly | Long-lived secret, used to mint short-lived secrets |
| Blast radius if leaked | Stranger acts as you on GitHub until revoked | Stranger mints keys until OAuth client revoked — but minted keys are tag-scoped and short-lived |

Both wind up age-encrypted in `ansible/secrets/`. The flows in the Ansible roles differ only because the APIs differ — PAT goes straight through to `gh auth login --with-token`; OAuth has an extra "exchange for access token, then mint a key" step.

## Lost the age key

If `secrets.local` is gone AND not in any password manager, every `.age` file in the repo is permanently unreadable. The recovery path is to bootstrap a new keypair and re-encrypt every secret with new plaintexts (since you can't recover the old plaintexts either). See [`recovery.md`](recovery.md) → "Age key lost (catastrophic)" for the step-by-step.

Nothing irrecoverable in the devbox itself depends on this — source lives in git, config lives in this repo. The catastrophic cost is the manual re-bootstrap of two GitHub credentials and one Tailscale OAuth client.

## Why age and not (sops, gpg, vault, …)

- **gpg**: heavier toolchain, key management nightmares, designed for federated trust networks we don't need.
- **sops** (Mozilla's tool): great for multi-recipient editing of structured files, but our secrets are blobs (a key, a token, a secret string) and we have one recipient. Sops would be overkill.
- **Vault / SSM / cloud KMS**: requires *another* always-on service to be reachable from the controller. We want the laptop to be self-sufficient for provisioning.
- **age**: 100 KB Go binary, one keypair, simple CLI, files are forward-compatible. Fits the personal-scale shape exactly.

If we ever grow to a multi-person setup, we'd re-evaluate. For one developer, age is the right tradeoff.
