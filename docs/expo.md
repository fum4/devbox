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
| **VPS interactive shell** (`bunx eas-cli@latest …` over Termius/Zellij) | `expo-identity` role decrypts `expo-<app>.age` on the laptop into `~/.config/expo/<app>.token` (mode 0600). Each app's repo wires its own `EXPO_TOKEN` from that file via mise — kost's `.mise.toml` `[env]` reads `~/.config/expo/kost.token`, so the token is set **only inside that repo**. |
| **GitHub Actions** (`build-mobile.yml`, `update-mobile.yml`) | A repo-level Actions secret `EXPO_TOKEN`. Actions can't read the age store, so it's synced separately with `gh secret set`. |

The `.age` file is the **canonical source**; the token file and the Actions
secret are synced copies. Per-repo wiring (not a global export) is what lets
multiple Expo apps coexist — see [Multiple Expo apps](#multiple-expo-apps).

## Trust model

Same as [`secrets.md`](secrets.md): the age **private key** (`secrets.local`)
lives only on the laptop; encryption + provisioning happen there. The token does
land at rest on the VPS (in `~/.config/expo/<app>.token`) — like the GitHub PAT does — so an
attacker with root on the box could read it. Scope it accordingly when you create
it (an EAS access token can be revoked independently at any time).

## Multiple Expo apps

EAS CLI always reads the env var **`EXPO_TOKEN`** — you can't scope by var name.
So the whole pipeline is scoped per app, and `EXPO_TOKEN` is wired **per repo**
(never globally) so two apps never collide. The pattern for an app `<app>`:

| Layer | Name |
|---|---|
| Expo robot user | `<app>-eas` |
| age secret | `ansible/secrets/expo-<app>.age` |
| token file on the VPS | `~/.config/expo/<app>.token` (laid down by `expo-identity`) |
| env var (fixed) | `EXPO_TOKEN`, set by that repo's `.mise.toml` `[env]` from its token file |

Adding an app is mechanical: create robot `<app>-eas`, encrypt its token to
`expo-<app>.age`, re-run the role (it globs `expo-*.age` → one token file each),
and add the one-line `[env]` to that repo's `.mise.toml`. When the token file is
absent (CI, or pre-bootstrap) mise sets `EXPO_TOKEN` **empty** — EAS treats that
as no token, so nothing breaks.

## One-time bootstrap (on your laptop)

### 1. Create the EAS access token

expo.dev → **Account settings → Access tokens**. Either:

- **Robot user** (recommended for CI — scoped, not tied to a person): *Add robot*
  → name it **`kost-eas`** → role **Admin** (needs build + submit + update) →
  *Create token*; or
- **Personal access token**: *Create token* at the top of the page.

Copy it — shown only once.

### 2. Encrypt it into the repo

```bash
cd ~/_work/devbox
AGE_PUB=$(grep -o 'age1[0-9a-z]*' secrets.local | head -1)
read -rs EXPO_TOKEN                         # paste the token — not echoed, not in history
printf '%s' "$EXPO_TOKEN" | age -r "$AGE_PUB" -o ansible/secrets/expo-kost.age
unset EXPO_TOKEN
git add ansible/secrets/expo-kost.age && git commit -m "chore(secrets): add expo-kost"
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
# On the VPS, from INSIDE the app repo (mise sets EXPO_TOKEN there):
cd ~/code/kost && echo "${EXPO_TOKEN:+EXPO_TOKEN is set}"
bunx eas-cli@latest whoami                  # prints the Expo account

# CI: the build-mobile / update-mobile workflows now authenticate.
```

## Rotation

Revoke the old token at expo.dev, then repeat steps 1–4 with a new one
(re-encrypt overwrites `expo-kost.age`; re-run the role; re-set the CI secret).

## Before bootstrap — using EAS from the phone right now

Until the laptop bootstrap, drop the token file mise reads — it works
immediately inside the app repo and is the same file the role lays down later:

```bash
mkdir -p ~/.config/expo
read -rs t && printf '%s' "$t" > ~/.config/expo/kost.token && unset t
chmod 600 ~/.config/expo/kost.token
# …or fully interactive from any dir (ephemeral, dies on rebuild):
bunx eas-cli@latest login
```

(Prefer the file over `export EXPO_TOKEN=…`: mise re-applies the repo's `[env]`
on each prompt and would clobber a manual export inside the repo.)
