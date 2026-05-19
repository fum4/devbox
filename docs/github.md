# GitHub identity for the devbox

This document covers the **persistent GitHub identity** used by the devbox: a long-lived SSH key + a personal access token (PAT), both stored age-encrypted in this repo and decrypted by Ansible during provision. The goal: **eliminate the interactive `gh auth login` browser flow on every VPS rebuild.**

> Sister docs: [`laptop.md`](laptop.md) (the controller side this depends on), [`secrets.md`](secrets.md) (the encryption pattern used here), [`provisioning.md`](provisioning.md) (when this role runs during provisioning), [`recovery.md`](recovery.md) (what to do when it breaks).

## Why

Without this, every fresh provision requires:

1. `ssh devbox`
2. `gh auth login` → OAuth flow → enter code at github.com → upload SSH key via gh
3. Re-run `ansible-playbook ... --tags repos`

That's ~3 min of friction every rebuild. With this set up, all three steps disappear — `ansible-playbook ... site.yml` runs end-to-end.

## Architecture

```
LAPTOP                                          VPS
──────                                          ───

devbox/secrets.local   (age private key)
                  ──┐
                    │ decrypts at playbook runtime
                    ▼
devbox/ansible/secrets/
├── github-fum4.age   (encrypted SSH private key)  ──→ ~/.ssh/github-fum4         (0600)
└── github-pat.age    (encrypted GitHub PAT)       ──→ gh auth login --with-token
                                                       writes ~/.config/gh/hosts.yml
```

- The **age private key** (`devbox/secrets.local`) lives only on your laptop. Back it up to a password manager.
- The **encrypted secrets** are safe to commit to the devbox repo.
- The **decrypted plaintext** never leaves the controller — Ansible decrypts in memory and pushes the bytes directly to the VPS over SSH.

## Trust model

- Anyone who steals `devbox/secrets.local` from your laptop can decrypt the secrets in the repo. Treat it like an SSH private key — never email, never paste, never share.
- Anyone who steals the VPS's `~/.ssh/github-fum4` can push code as you to GitHub. Mitigated by GitHub instant key revocation + `wt`'s `--force-with-lease` keeping accidental damage bounded.
- The PAT scopes are limited (`repo` + `read:org` + `workflow`) — wide enough for normal git ops, narrow enough that compromise is recoverable by rotation.

## One-time bootstrap (on your laptop)

Do this once. It produces three things: an age keypair, an encrypted SSH key in the repo, and an encrypted PAT in the repo.

### 1. Install age

```bash
brew install age
```

### 2. Generate the age keypair

The private key lives at `devbox/secrets.local` (gitignored via `*.local`). Sits alongside the encrypted `.age` files in `ansible/secrets/` but separated from them — committed: encrypted; uncommitted: the key.

```bash
cd ~/_work/devbox
age-keygen -o secrets.local
chmod 600 secrets.local
```

This writes the private key + a public-key comment line at the top of the file:

```
# created: 2026-05-20T...
# public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxx
AGE-SECRET-KEY-1xxxxxxxxxxxxxxxxxxxxxxxx
```

**Copy the public key** (the `age1...` string) — you'll use it as the encryption recipient.

**Back up `devbox/secrets.local`** to your password manager (1Password, Bitwarden, etc.) RIGHT NOW. If you lose this key, you cannot decrypt the secrets in the repo, and you'll have to re-bootstrap from scratch (regenerate keys + tokens + re-encrypt + revoke the old ones on GitHub).

### 3. Generate the GitHub SSH key

```bash
ssh-keygen -t ed25519 -C "fum4-devbox-identity" -f /tmp/github-fum4 -N ""
```

This is a **long-lived** key that lives encrypted in the repo and is used by every devbox you'll ever provision. It is **distinct** from your laptop's GitHub keys.

### 4. Encrypt the SSH private key into the repo

Replace `<AGE_PUBKEY>` with the value from step 2:

```bash
cd ~/_work/devbox
mkdir -p ansible/secrets
age -e -r <AGE_PUBKEY> -o ansible/secrets/github-fum4.age /tmp/github-fum4
```

Commit later (after step 7).

### 5. Register the SSH public key with GitHub

```bash
pbcopy < /tmp/github-fum4.pub
```

Then https://github.com/settings/keys → **New SSH key** → title `devbox` → paste → Add.

### 6. Generate the PAT

https://github.com/settings/tokens/new

- Note: `devbox`
- Expiration: 1 year (rotatable)
- Scopes: `repo`, `read:org`, `workflow`

Click Generate token. Copy the `ghp_…` value to clipboard, then:

```bash
pbpaste > /tmp/gh-pat.txt
```

### 7. Encrypt the PAT into the repo

```bash
age -e -r <AGE_PUBKEY> -o ansible/secrets/github-pat.age /tmp/gh-pat.txt
```

### 8. Clean up plaintext + commit

```bash
shred -u /tmp/github-fum4 /tmp/github-fum4.pub /tmp/gh-pat.txt 2>/dev/null \
    || rm /tmp/github-fum4 /tmp/github-fum4.pub /tmp/gh-pat.txt

cd ~/_work/devbox
git add ansible/secrets/github-fum4.age ansible/secrets/github-pat.age
git commit -m "chore(secrets): add age-encrypted github identity"
git push
```

Bootstrap done. The repo now contains the encrypted identity. Every future devbox rebuild will use it automatically.

## Wiring on the VPS

The `github-identity` Ansible role runs as part of `site.yml`, after `dotfiles` and before `repos`. On every provision, it:

1. Checks that both `.age` files exist (skips with a notice if not — useful for the first provision before you've bootstrapped)
2. Decrypts each on the laptop using `devbox/secrets.local`
3. Writes the SSH key to `~/.ssh/github-fum4` (mode 0600)
4. **Regenerates a matching `.pub` file** from the just-installed private (avoids OpenSSH offering a stale public key from any prior `gh auth login`)
5. Adds a `Host github.com` block to `~/.ssh/config` (via Ansible's `blockinfile` with a managed marker — re-runs are idempotent)
6. Adds GitHub's host key to `~/.ssh/known_hosts` (no first-clone prompt)
7. Pipes the PAT into `gh auth login --with-token` (skipped if gh is already authed)

After it runs:

- `ssh -T git@github.com` returns `Hi fum4!`
- `gh auth status` returns `Logged in to github.com as fum4`
- `git clone git@github.com:fum4/<repo>.git` works without further auth

The `repos` role (which runs immediately after) can now clone everything in `repos.txt` on the first try.

## Verifying after a rebuild

```bash
ssh devbox 'ssh -T git@github.com && gh auth status'
```

Both should succeed. If either fails, see [Troubleshooting](#troubleshooting).

## Rotation

### PAT rotation (~yearly, before expiry)

PATs expire. When you get a GitHub email warning of expiry, or when you want to rotate proactively:

```bash
# 1. Generate a fresh PAT (same scopes) at github.com/settings/tokens/new
# 2. Copy it
pbpaste > /tmp/gh-pat.txt

# 3. Re-encrypt — overwrites the old file
age -e -r <AGE_PUBKEY> -o ansible/secrets/github-pat.age /tmp/gh-pat.txt

# 4. Clean up + commit
shred -u /tmp/gh-pat.txt 2>/dev/null || rm /tmp/gh-pat.txt
git add ansible/secrets/github-pat.age
git commit -m "chore(secrets): rotate github pat"
git push

# 5. Re-run the role on every devbox you have running
cd ansible
ansible-playbook -i inventory.ini site.yml --tags github-identity

# 6. Delete the old token on github.com/settings/tokens
```

### SSH key rotation (on compromise or by choice)

```bash
# 1. Generate a fresh key
ssh-keygen -t ed25519 -C "fum4-devbox-identity" -f /tmp/github-fum4 -N ""

# 2. Re-encrypt
age -e -r <AGE_PUBKEY> -o ansible/secrets/github-fum4.age /tmp/github-fum4

# 3. Upload the new public key to GitHub
pbcopy < /tmp/github-fum4.pub
# → github.com/settings/keys → New SSH key → title `devbox` → paste → Add

# 4. Clean + commit
shred -u /tmp/github-fum4 /tmp/github-fum4.pub 2>/dev/null \
    || rm /tmp/github-fum4 /tmp/github-fum4.pub
git add ansible/secrets/github-fum4.age
git commit -m "chore(secrets): rotate github ssh key"
git push

# 5. Re-run the role on every devbox
ansible-playbook -i inventory.ini ansible/site.yml --tags github-identity

# 6. Delete the OLD `devbox` SSH key on github.com/settings/keys
```

### Age key rotation (only if compromised — catastrophic)

If `devbox/secrets.local` is ever exposed, you need to re-bootstrap *everything*:

1. Generate a new age keypair (`age-keygen` again, overwriting `devbox/secrets.local`)
2. Treat the existing `.age` files in the repo as compromised — generate fresh SSH key + PAT
3. Encrypt them with the **new** age recipient
4. Replace both `.age` files in the repo
5. Upload the new SSH pub to GitHub; delete the compromised one
6. Generate a new PAT; revoke the compromised one
7. Commit + push
8. Re-provision every devbox

## Troubleshooting

### "age: no identity matched any recipient"

The `.age` file in the repo was encrypted to a different age public key than the one in `devbox/secrets.local`. Either:

- Wrong age key on this machine — restore the right one from your password manager.
- The repo's `.age` files were re-encrypted by someone else. Coordinate with them or re-bootstrap.

### "age: error: failed to read header"

The file isn't a valid age ciphertext. Likely the `.age` file got corrupted or wasn't written via `age -e`. Re-encrypt.

### `gh auth status` shows "not logged in" after role runs

The PAT was likely rejected. Causes:

- PAT expired — rotate per above
- PAT has wrong scopes — regenerate with `repo` + `read:org` + `workflow`
- PAT was revoked on github.com/settings/tokens — regenerate + re-encrypt

### `ssh -T git@github.com` fails with `Permission denied (publickey)`

In likelihood order:

- **Stale `.pub` on the VPS** — OpenSSH advertises the public key from `~/.ssh/github-fum4.pub` (next to the private). If a previous `gh auth login` left a different `.pub`, you'll offer the wrong key. The `github-identity` role regenerates the `.pub` from the just-installed private to prevent this — re-run with `--tags github-identity`. Or manually: `ssh devbox 'ssh-keygen -y -f ~/.ssh/github-fum4 > ~/.ssh/github-fum4.pub'`.
- **The SSH public key in the repo's `.age` doesn't match what's on github.com/settings/keys.** Verify with:
  ```bash
  age -d -i devbox/secrets.local ansible/secrets/github-fum4.age > /tmp/k
  chmod 600 /tmp/k && ssh-keygen -y -f /tmp/k > /tmp/k.pub
  ssh-keygen -lf /tmp/k.pub
  shred -u /tmp/k /tmp/k.pub
  ```
  Compare the fingerprint to https://github.com/settings/keys → `devbox` entry. If they differ, the key in the repo isn't what's registered — either re-upload from your stored copy, or rotate per [Rotation](#ssh-key-rotation-on-compromise-or-by-choice).
- **Permissions on the VPS** — must be 0600. The role sets this; if you've manually edited the file, re-run `--tags github-identity`.

### "Could not resolve hostname github.com"

The VPS has lost network. Unrelated to this setup.

## Recovery from total loss

If you've lost your age key AND your laptop:

1. On a new laptop, install age.
2. Generate a brand-new age keypair.
3. Treat the repo's `.age` files as garbage — you can't decrypt them.
4. Follow the bootstrap steps from scratch (new SSH key, new PAT, encrypt with new age key, push).
5. On GitHub: delete the old `devbox` SSH key (you don't have its private half anyway). Delete the old PAT.
6. Re-provision every VPS that was relying on the old identity.

This is recoverable — nothing in the devbox is irreplaceable except the source code (which is in git).
