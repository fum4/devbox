# Laptop setup

Take a fresh macOS install (or a laptop where you've lost the setup) and bring it to the point where you can run `ansible-playbook` against a Hetzner VPS and drive agents from this machine. Once this is done, the laptop becomes the *controller* for everything else.

**End state**: Homebrew installed, age/ansible/gh on PATH, SSH keys generated and registered with the right accounts, `~/_work/devbox/` cloned with its `secrets.local` restored from your password manager.

## Prerequisites

- macOS (Apple Silicon or Intel)
- Internet
- Access to your password manager (1Password, Bitwarden, etc.) — specifically the entry holding the **devbox age private key**

## 1. Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the prompts. After it finishes, **read the post-install message carefully** — on Apple Silicon you need to add `/opt/homebrew/bin` to your shell's PATH. The installer prints the exact two-line snippet to paste into `~/.zprofile`.

Verify:

```bash
brew --version
```

## 2. Install the core CLI tools

```bash
brew install age ansible gh git
```

That's it for the brews needed in this session. Other tooling (mise, claude, zellij, etc.) gets installed *on the devbox VPS*, not the laptop.

Verify:

```bash
age --version
ansible --version
gh --version
```

## 3. Generate SSH keys

You need two keys on this laptop:

| Key file | Purpose | Comment to use |
|---|---|---|
| `~/.ssh/id_ed25519_github_fum4` | Laptop → GitHub (fum4 account) for push/pull from this machine | `fum4-laptop-github` |
| `~/.ssh/id_ed25519_devbox_hetzner` | Laptop → Hetzner VPS for SSH-in / Ansible | `fum4-laptop-devbox` |

**Important**: these are *laptop-only* keys. The devbox VPS has *its own* GitHub identity (the persistent age-encrypted one in `ansible/secrets/github-fum4.age`). Don't conflate them.

Generate both:

```bash
ssh-keygen -t ed25519 -C "fum4-laptop-github"  -f ~/.ssh/id_ed25519_github_fum4   -N ""
ssh-keygen -t ed25519 -C "fum4-laptop-devbox"  -f ~/.ssh/id_ed25519_devbox_hetzner -N ""
```

(Add a passphrase if you want; leaving empty is fine for personal use as long as the laptop disk is FileVault-encrypted.)

## 4. Configure `~/.ssh/config`

This is what makes `ssh devbox` and `git push origin main` route through the right keys.

```bash
cat > ~/.ssh/config <<'EOF'
Host github.com
  HostName github.com
  User git
  AddKeysToAgent yes
  UseKeychain yes
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519_github_fum4

Host devbox
  HostName <fill-in-after-VPS-is-created>
  User fum4
  IdentityFile ~/.ssh/id_ed25519_devbox_hetzner
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
```

You'll fill in `HostName` for `devbox` when you create the VPS — see [rebuild.md](rebuild.md).

If you have *multiple* GitHub accounts (e.g., a personal `fum4` and a work `acedisplays`), define each as its own Host:

```
Host github-acedisplays
  HostName github.com
  User git
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519_github_acedisplays
```

Then clone work repos with `git clone git@github-acedisplays:org/repo.git`. The `Host` alias decides which identity SSH offers.

## 5. Register the GitHub key with your fum4 account

```bash
pbcopy < ~/.ssh/id_ed25519_github_fum4.pub
```

Open https://github.com/settings/keys → **New SSH key** → title `laptop` → paste → **Add SSH key**.

Verify:

```bash
ssh -T git@github.com
# Expected: Hi fum4! You've successfully authenticated...
```

## 6. Register the laptop's SSH key with Hetzner (only when you actually need it)

This step happens when you set up the Hetzner project — see [hetzner.md](hetzner.md). On a brand-new account:

```bash
pbcopy < ~/.ssh/id_ed25519_devbox_hetzner.pub
```

Then in Hetzner Console → your project → **Security** → **SSH Keys** → **Add SSH Key**, paste, name it `laptop`.

## 7. Clone the devbox repo

```bash
mkdir -p ~/_work
cd ~/_work
git clone git@github.com:fum4/devbox.git
cd devbox
```

If `git clone` fails with "Permission denied (publickey)" → step 5 (GitHub key registration) didn't work. Re-check.

## 8. Restore `secrets.local` from your password manager

This is the **age private key** that decrypts everything in `ansible/secrets/*.age`. If you don't have a password-manager entry for it, you'll have to re-bootstrap the GitHub identity per [github.md](github.md) → "Recovery from total loss."

Assuming you do have it backed up:

1. Open your password manager → find the entry titled something like *"devbox age private key"*.
2. Copy the entire content — it should look like:
   ```
   # created: ...
   # public key: age1xxxxx...
   AGE-SECRET-KEY-1xxxxxxxxxxx
   ```
3. On the laptop:
   ```bash
   cd ~/_work/devbox
   pbpaste > secrets.local
   chmod 600 secrets.local
   ```
4. Verify:
   ```bash
   age -d -i secrets.local ansible/secrets/github-pat.age | head -c 8
   # Expected: ghp_xxxx (a PAT prefix)
   ```

If decryption fails ("no identity matched any recipient"), the age key in your password manager doesn't match the one used to encrypt these secrets. You need to re-bootstrap — see [github.md](github.md).

## 9. Sanity check

```bash
cd ~/_work/devbox
ansible-playbook --syntax-check ansible/site.yml
ls -la secrets.local                           # should exist, mode 600
git status                                     # working tree should be clean
```

If all three are happy, the laptop is ready. Next: create a Hetzner VPS ([hetzner.md](hetzner.md)) and provision it ([rebuild.md](rebuild.md)).

## What you DON'T need to install on the laptop

These all live *on the VPS*, not the laptop:

- mise, claude code, codex, zellij, claude-squad, process-compose, ntfy
- Node, Bun, pnpm (project versions managed per-repo via mise on the VPS)
- Docker (the VPS runs containerized project infra; the laptop doesn't)

If you find yourself reaching for them locally, you're in the wrong place — `ssh devbox` first.
