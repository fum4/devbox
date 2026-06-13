# Repo secrets & infra pattern — the canonical recipe

**Read this BEFORE scaffolding any repo's `secrets/` or `infra`/`terraform/`.**
Every fum4 repo handles its secrets the same way. Do **not** approximate from
memory or copy another repo's wrapper blindly — that's exactly how `ops` drifted
onto the wrong pattern (it copied the devbox-internal `bin/devbox-tf` +
repo-root `secrets.local` style instead of this one) and had to be redone.

Reference implementations: **tipso** (`tipso/`) and **ops** (`ops/`). When in
doubt, copy tipso's `tools/secrets.sh`, `secrets/`, and mise `secrets:*` tasks
verbatim and adjust the manifest.

> **Two different "secrets" worlds — don't confuse them:**
> - **The devbox's OWN identity secrets** (GitHub, Tailscale, …) live in
>   `devbox/ansible/secrets/*.age` under the **devbox** age key (`secrets.local`,
>   laptop-only). That's [`docs/secrets.md`](secrets.md) — NOT this doc.
> - **An app/infra repo's OWN secrets** (Terraform tokens, SSH keys, app env)
>   live in **that repo** under **its own** age key. That's this doc.

## The pattern

```
<repo>/
  secrets/
    recipients.txt          # the repo's age PUBLIC key (committed)
    *.age                   # encrypted secrets (committed)
    .gitignore              # ignore all but .age / recipients.txt / README / .gitignore
    README.md
  tools/secrets.sh          # decrypt/encrypt engine + the manifest
  .mise.toml                # secrets:decrypt | secrets:encrypt | secrets:check
```

- **Private key:** `~/.config/age/<repo>.key` (mode 0600). Root of trust = your
  **password manager**. Override with `<REPO>_AGE_KEY=…`.
- **`tools/secrets.sh`** holds a MANIFEST — `plaintext_path | age_path | mode |
  kind` — and `decrypt`/`encrypt`/`check` against it. `kind` is `file` or
  `sshkey` (the latter regenerates the `.pub` on decrypt).
- Secrets **materialize to gitignored plaintext on demand** (`mise run
  secrets:decrypt`); tools read the plaintext (Terraform reads `terraform.tfvars`,
  sources `.r2-backend.env`). Never commit plaintext or the private key.

## Env config: the repo is the source of truth; the runtime is fed from it

Applies to any repo whose app runs on a PaaS/runtime with its own env store
(Coolify, Vercel, Fly, …). **The repo is the source of truth for env config across
every environment (dev / staging / prod); the runtime is *fed* from the repo,
never the reverse.** A runtime that holds the only copy of its own input config is
a single point of loss — tipso lost its prod env when the Coolify control plane
was migrated and wiped, recoverable only from a nightly backup. "Durable in the
PaaS + a backup" is *recovery*, not a source of truth. Rules:

- **Explicit per-env encrypted files:** `secrets/<app>.<env>.env.age`
  (`api.dev.env.age`, `api.staging.env.age`, `api.prod.env.age`). One file per env
  — visible in `ls`, per-env blast radius, unambiguous to target.
- **A push tool feeds the runtime:** `mise run env:push <env>` decrypts that env's
  file and writes it into the env's runtime app over the runtime's API;
  `mise run env:diff <env>` verifies live ↔ repo (values redacted) to catch drift.
  Recovering an env's config is then **one command**, not a backup restore.
  Reference impl: tipso `tools/coolify-env.sh` + its ADR 0008.
- **Only real secrets in the `.age` files.** Non-secret flags (`NODE_ENV`, log
  level, feature toggles, model ids) live with the deploy manifest
  (compose / `vercel.json`) + the app's typed-config defaults — never duplicated
  into the secret files.
- **One source per env — no committed `.env.example`.** The app's typed env schema
  (e.g. `config/env.ts`, zod-parsed at boot) is the *contract*; `secrets/*.age` are
  the *values*; `secrets:decrypt` materializes the runtime `.env`. A committed
  `.env.example` is a second, drift-prone copy of the same thing — so onboarding is
  "restore the age key → `secrets:decrypt`", not "copy the example". (A keyless
  dev boot is the only thing lost — fine, the `repo-age-keys` role always installs
  the key.)

## Setting up a NEW repo's secrets

```bash
# 1. age key — store the PRIVATE key in your password manager ("<repo> age key")
age-keygen -o ~/.config/age/<repo>.key && chmod 600 ~/.config/age/<repo>.key
age-keygen -y ~/.config/age/<repo>.key            # -> secrets/recipients.txt

# 2. copy tipso's tooling, adjust the manifest paths + the AGE_KEY var name
cp tipso/tools/secrets.sh <repo>/tools/secrets.sh   # edit MANIFEST + <REPO>_AGE_KEY
cp tipso/secrets/.gitignore <repo>/secrets/.gitignore
#    add secrets:decrypt|encrypt|check tasks to .mise.toml

# 3. write the plaintext secrets, then encrypt + commit
mise run secrets:encrypt
git add secrets/*.age secrets/recipients.txt tools/secrets.sh && git commit && git push

# 4. ESCROW so a rebuilt devbox restores the key automatically (see below)
```

## Escrow — surviving a devbox rebuild

The `repo-age-keys` Ansible role **auto-discovers** every
`devbox/ansible/secrets/*-age-key.age`, decrypts it on the laptop (with the
devbox key), and installs it to `~/.config/age/<repo>.key` on the box. So to make
a repo's key survive a rebuild, just add its escrowed key — **no role edit**:

```bash
# on the LAPTOP (needs the devbox recipient from secrets.local)
DEVBOX_REC=$(grep -o 'age1[0-9a-z]*' ~/_work/devbox/secrets.local | head -1)
age -e -r "$DEVBOX_REC" -o ~/_work/devbox/ansible/secrets/<repo>-age-key.age ~/.config/age/<repo>.key
git -C ~/_work/devbox add ansible/secrets/<repo>-age-key.age && git -C ~/_work/devbox commit -m "chore(secrets): escrow <repo> age key" && git push
```

Filename **must** be `<repo>-age-key.age` → installs to `~/.config/age/<repo>.key`
(what `tools/secrets.sh` expects). Existing escrows: `tipso-age-key.age`,
`accounting-age-key.age`.

## Infra (Terraform) goes with it

A repo that provisions infra keeps its `terraform/` in the **same repo**, with:
- State in a private **R2** bucket `<repo>-backup`, key `terraform/<repo>.tfstate`
  (S3 backend; creds from `secrets/r2-backend.env.age` → `.r2-backend.env`).
- The R2 **Account** API token `<repo>-terraform-state`, Object R/W, scoped to
  `<repo>-backup` (EU). Buckets/tokens use this naming across all repos.
- Provider tokens in `secrets/terraform.tfvars.age` → `terraform.tfvars`.

This pairs with the AGENTS.md rules "Provision infrastructure with Terraform,
always" and "Infra state & creds are global doctrine".
