# Expo / EAS token for the devbox

How the devbox authenticates with Expo Application Services (EAS) — `eas build`,
`eas submit`, `eas update` — without an interactive `eas login` that dies on the
next rebuild.

> Sister docs: [`secrets.md`](secrets.md) (the age-encryption pattern this uses),
> [`github.md`](github.md) (the same pattern for GitHub).

## Why

`eas login` stores a session token under `~/.expo` on the box. The VPS is
ephemeral — a rebuild wipes it, and you'd have to re-login by hand (with 2FA)
from the phone. Instead we store an **EAS access token** (`EXPO_TOKEN`) the same
way we store the GitHub identity: age-encrypted in the repo, installed at
provision time. EAS CLI reads `EXPO_TOKEN` from the environment and skips
interactive login entirely.

## Architecture

| Consumer | How it gets the token |
|---|---|
| **VPS interactive shell** (`bunx eas-cli@latest …` over Termius/Zellij) | `expo-identity` role decrypts `expo-token.age` on the laptop and writes `export EXPO_TOKEN=…` into `~/.bashrc.local` (mode 0600, sourced by `~/.bashrc`). |
| **GitHub Actions** (`build-mobile.yml`, `update-mobile.yml`) | A repo-level Actions secret `EXPO_TOKEN`. Actions can't read the age store, so it's synced separately with `gh secret set`. |

The `.age` file is the **canonical source**; the Actions secret is a synced copy.
`~/.bashrc.local` only applies to *interactive* shells — that's fine, the VPS
only runs `eas` interactively; CI uses its own secret.

## Trust model

Same as [`secrets.md`](secrets.md): the age **private key** (`secrets.local`)
lives only on the laptop; encryption + provisioning happen there. The token does
land at rest on the VPS (in `~/.bashrc.local`) — like the GitHub PAT does — so an
attacker with root on the box could read it. Scope it accordingly when you create
it (an EAS access token can be revoked independently at any time).

## One-time bootstrap (on your laptop)

### 1. Create the EAS access token

expo.dev → **Account settings → Access tokens → Create token**. Copy it (you
only see it once).

### 2. Encrypt it into the repo

```bash
cd ~/_work/devbox
AGE_PUB=$(grep -o 'age1[0-9a-z]*' secrets.local | head -1)
read -rs EXPO_TOKEN                         # paste the token — not echoed, not in history
printf '%s' "$EXPO_TOKEN" | age -r "$AGE_PUB" -o ansible/secrets/expo-token.age
unset EXPO_TOKEN
git add ansible/secrets/expo-token.age && git commit -m "chore(secrets): add expo-token"
```

### 3. Install it on the VPS

From the laptop, run the normal provision (see [`provisioning.md`](provisioning.md)),
or just the one role:

```bash
cd ansible && ansible-playbook -i inventory.ini site.yml --tags expo-identity
```

### 4. Sync the CI secret

GitHub Actions can't read the age store, so push the same token to the repo:

```bash
gh secret set EXPO_TOKEN -R fum4/kost       # paste the same token
```

### 5. Verify

```bash
# On the VPS (open a fresh shell so ~/.bashrc.local is sourced):
echo "${EXPO_TOKEN:+EXPO_TOKEN is set}"
bunx eas-cli@latest whoami                  # prints the Expo account

# CI: the build-mobile / update-mobile workflows now authenticate.
```

## Rotation

Revoke the old token at expo.dev, then repeat steps 1–4 with a new one
(re-encrypt overwrites `expo-token.age`; re-run the role; re-set the CI secret).

## Before bootstrap — using EAS from the phone right now

Until the token is installed you can still work interactively:

```bash
bunx eas-cli@latest login                   # interactive, ephemeral (dies on rebuild)
# or, for the current shell only:
export EXPO_TOKEN=<token>
```
