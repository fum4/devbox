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
| `ansible/secrets/apple-signin-key.age` | Apple *Sign in with Apple* private key (`.p8`, Team `SWXC85YFF4`) | **Nobody** — recovery backup only. Clerk holds the live copy; Apple lets you download the `.p8` just once. Team-scoped (serves any Sign-in-with-Apple app, not only Tipso). | **No** — never installed; decrypt on the laptop only to re-enter it into Clerk. |
| `ansible/secrets/tipso-age-key.age` | the **tipso repo's** age private key | `repo-age-keys` role → `~/.config/age/tipso.key` (mode 0600). Lets the box run `mise run secrets:decrypt` in `~/code/tipso`. | Yes (the box decrypts that repo's secrets locally) |
| `ansible/secrets/accounting-age-key.age` | the **accounting-sync repo's** age private key | `repo-age-keys` role → `~/.config/age/accounting.key` (mode 0600). | Yes (same) |
| `ansible/secrets/hetzner-token.age` | Hetzner Cloud API token (R/W, devbox project) | `bin/devbox-tf` (not Ansible) → decrypted in memory, injected as `HCLOUD_TOKEN` for Terraform. See [`terraform.md`](terraform.md). | **No** — laptop-only, in memory |
| `ansible/secrets/r2-devbox-state.age` | R2 access keys for the `devbox-backup` state bucket (env-file lines: `AWS_ACCESS_KEY_ID=…`, `AWS_SECRET_ACCESS_KEY=…`) | `bin/devbox-tf` (not Ansible) → sourced in memory for the Terraform S3 backend. | **No** — laptop-only, in memory |

Why five secrets, three patterns: the OAuth `client_secret` is more powerful than the keys it mints, so we keep it on the controller. The GitHub PAT and SSH key are what the VPS actually needs in operation, so they have to live there. The Apple sign-in key is the third pattern: a recovery-only copy that no role consumes — encrypted in git purely so a one-time-download `.p8` is never lost. See [the PAT/OAuth explainer](#why-the-different-shapes) below.

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

## Scope: this store is for the *box's own* secrets

The store above holds the devbox's **own identity** secrets — the credentials
*the box itself* needs to be itself (its GitHub identity, its place in the
tailnet, its Expo build auth). It is **not** a dumping ground for every repo's
secrets.

The universal rule (codified in `agents/AGENTS.md`) is about *encryption*, not
*location*: **no secret may exist only as gitignored plaintext** — it must be
encrypted-at-rest somewhere durable, with the root of trust in your password
manager. *Where* the ciphertext lives depends on **who owns the secret**:

| Secret kind | Lives where | Key |
|---|---|---|
| The box's own identity (GitHub, Tailscale, Expo) | here, `ansible/secrets/*.age` | the devbox age key (laptop-only) |
| A repo's deploy/dev secrets (its tokens, `.env`s, deploy keys) | **in that repo**, encrypted | that **repo's own** age key |
| A repo's **age key** itself (the bridge) | here, `ansible/secrets/<repo>-age-key.age` | the devbox age key |

That last row is the one exception that proves the rule: a repo's *secrets* stay
in the repo, but its **age key** is delivered by the devbox (via `repo-age-keys`)
so a freshly-rebuilt box can decrypt them without a manual paste from your
password manager. We carry the *key*, not the secrets.

Keeping a repo's secrets *in the repo* keeps it self-contained (clone it + have
its key → decrypt and run; no need to drag this repo along) and contains the
blast radius (a repo's key can't decrypt the box's identity, and can be handed to
that repo's CI in isolation). That's the professional default — see kost's
`docs/decisions/0006-secret-handling.md` for the full reasoning.

**The devbox's role in the per-repo model is key *delivery*, not storage.** A repo
consumed *on this box* (e.g. you run its `terraform` / `mise run dev` here) needs
its age key present to decrypt. So the box delivers each such repo's age key the
same laptop-only way it delivers its own identity: the repo's age **private** key
is encrypted under the *devbox* key as `ansible/secrets/<repo>-age-key.age`, and a
small role decrypts it on the laptop and drops it at the path that repo's decrypt
task expects. The repo owns its encrypted *secrets*; the devbox just makes sure
its *key* is on the box.

> **Foundation (independent of any repo):** the password manager must hold the
> **age private keys** (the devbox's and each repo's) *and* the **provider account
> logins + 2FA recovery codes** (Cloudflare, Hetzner, Vercel, Clerk, OpenRouter,
> GitHub, …). Those account logins are the true root — regenerating any token
> assumes you can still log in. See `TODO.md` for the pending kost age-key
> delivery role.

## Global doctrine: age-in-git, keys in the password manager, state/backups in R2

The patterns above aren't devbox-only — they're the **house rules for every repo**.
A repo may add its own specifics, but the general shape is global:

1. **Encrypt everything with `age`, committed to git.** No secret ever exists only
   as gitignored plaintext. Ciphertext (`*.age`) lives next to whoever owns it.
2. **Age private keys live in the password manager (Bitwarden).** That — plus the
   provider account logins + 2FA recovery codes — is the root of trust. One key per
   owner (the devbox's, each repo's), so a leak is contained and a key can be handed
   to that repo's CI in isolation. The devbox *delivers* a repo's key; it doesn't
   *store* the repo's secrets.
3. **Durable state & backups live in Cloudflare R2.** Terraform state and any
   nightly backups go to a **private, per-repo R2 bucket** (S3 backend), so a lost
   laptop/devbox never orphans live infra — `terraform init` re-pulls it. The state
   bucket is created **out-of-band** (bootstrap exception: the bucket holding
   Terraform's own state can't be managed by that same Terraform).

### The two lanes of secrets

Both lanes store the same way — **age-encrypted in git, always**. The lanes differ
only in *who consumes the plaintext and where*:

- **Lane 1 — Ansible-delivered**: a box/repo's *identity* secrets (GitHub key/PAT,
  Tailscale OAuth, …). Decrypted on the laptop at playbook time; some plaintexts
  are pushed to the box because the box needs them in operation.
- **Lane 2 — Terraform-consumed**: what a `terraform apply` needs — the Hetzner
  token (`hetzner-token.age`) and the R2 state-backend keys (`r2-devbox-state.age`).
  Decrypted **in memory** by `bin/devbox-tf` on the laptop and injected as env vars
  (`HCLOUD_TOKEN`, `AWS_*`); the plaintext never touches disk and **never reaches
  the box**. tipso does the same with its own age key (`secrets/*.age` +
  `mise run secrets:decrypt`).

> **The hard rule — do not drift from this.** The password manager (Bitwarden)
> holds **only** (a) age private keys and (b) provider account logins + 2FA
> recovery codes. **Never** store an individual API token/key as a loose
> password-manager entry, and **never** leave one as gitignored plaintext
> (`*.tfvars`, `.env`, …) as its only durable home. If you mint a token, the same
> sitting isn't over until it's `age`-encrypted and committed next to its owner.
> A token that exists anywhere else is drift — re-encrypt it or revoke it.

**Cross-repo rule:** each repo owns its own infra (`infra/terraform/` + its own state
bucket); the devbox provisions only *itself* (`terraform/devbox/`). Reference
implementation + recover/rotate/disaster runbooks: tipso `infra/terraform/` and
`tipso/docs/runbooks/{secrets,disaster-recovery}.md`. Devbox-specific Terraform
mechanics: [`terraform.md`](terraform.md).

### Minting anything new? Walk this checklist

Every drift incident so far happened by *skipping a question below*, not by not
knowing the rules. Before creating any credential, token, key, or state store —
answer these **in order**, out loud, before clicking "create":

1. **Who owns it?** The repo whose system consumes it. Devbox's own existence/
   identity → devbox repo. A product's deploy/infra → that product's repo. Never
   park one repo's secret in another repo "for convenience".
2. **Does the owner have an age key yet?** Existing repo with secrets → use its
   key. A repo minting its **first** secret → first `age-keygen` a keypair for
   it, put the private key in **Bitwarden** (entry: *"<repo> age key"*), deliver
   it where it's consumed (laptop file / `repo-age-keys` role). This is the
   **only** thing that ever goes into Bitwarden.
3. **Scope the credential minimally.** One bucket, one project, least
   permission. An "all buckets / admin" token is a finding, not a convenience
   (see the `tipso-terraform-r2` incident — an undocumented account-wide admin
   token nobody could identify two days later).
4. **Encrypt before the sitting ends.** `age -r <owner's recipient>` → commit in
   the owner's repo. The plaintext on your clipboard/screen is the only copy
   outside git — it should die with the browser tab.
5. **Document it where its owner documents secrets** — same commit. Devbox:
   the inventory table above. tipso: its `docs/runbooks/secrets.md`. A token
   that's not in its owner's inventory doc doesn't exist as far as the next
   session is concerned — that's how mystery credentials are born.
6. **Terraform state?** Per-repo R2 bucket (`<repo>-backup`), EU, created
   out-of-band, accessed via an Account API token scoped to that bucket only —
   which itself goes through steps 1–5.

If a credential already exists somewhere that violates this (a loose Bitwarden
entry, a gitignored plaintext, an unscoped token), **fix it now or revoke it** —
don't build on top of drift.

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
