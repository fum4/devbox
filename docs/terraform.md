# Terraform: the devbox VPS as code

`terraform/devbox/` makes the box's *existence* declarative, the way Ansible
already makes its *contents* declarative. It closes the last click-ops island:
before this, creating the VPS was a Hetzner-UI safari ([hetzner.md](hetzner.md))
and every rebuild changed the IP, forcing edits to `~/.ssh/config`,
`ansible/inventory.ini`, and known_hosts.

> Sister docs: [hetzner.md](hetzner.md) (account/project/token — the parts that
> stay manual), [provisioning.md](provisioning.md) (the Ansible runbook that
> takes over after `apply`), [secrets.md](secrets.md) → "Global doctrine" (the
> state + credential strategy this implements).

> All commands run **on the laptop** — decryption needs `secrets.local` (the
> devbox age key, laptop-only), and a dead box can't rebuild itself. Use the
> **`bin/devbox-tf`** wrapper, which decrypts the creds in memory and forwards
> to `terraform`.

## The layer cake

| Layer | Tool | Owns |
|---|---|---|
| **Existence** | Terraform (`terraform/devbox/`) | server, **stable primary IP**, cloud firewall, SSH key registration |
| Configuration | Ansible (`ansible/`) | everything inside the box — unchanged by this |
| Dotfiles/sessions | chezmoi / systemd | unchanged |

The seam is deliberate: **zero cloud-init**. Hetzner's debian-12 image already
has what Ansible's first run needs (python3 + root's authorized_key). Terraform
hands over a reachable box; `provisioning.md` §3 takes it from there.

## What each resource is for

| Resource | Why |
|---|---|
| `hcloud_primary_ip.devbox` | **The stable IP.** `auto_delete=false` + `prevent_destroy`: it survives server destruction, so the IP — and every config file that mentions it — never changes across rebuilds. The asset this config exists to protect. |
| `hcloud_server.devbox` | The box. Deliberately **disposable** (no `prevent_destroy`): destroy + apply *is* the rebuild flow. |
| `hcloud_firewall.devbox` | Network-edge default-deny; one inbound rule (SSH/22). Tailscale needs no inbound rule (outbound-initiated, DERP fallback). The on-box ufw stays as the host-level layer. |
| `hcloud_ssh_key.devbox` | Registers the laptop's `~/.ssh/devbox_vps.pub` so a fresh box accepts root SSH on first boot. |

## Credentials and state

**No cred files exist, anywhere.** Both Terraform credentials are age-encrypted
in the repo's secret store — the same store as everything else ([secrets.md](secrets.md)
→ "The two lanes of secrets", lane 2). `bin/devbox-tf` decrypts them **in
memory** with `secrets.local` and injects them as env vars; plaintext never
touches disk and never reaches the box:

| File (committed) | Holds | Injected as |
|---|---|---|
| `ansible/secrets/hetzner-token.age` | Hetzner API token (R/W, devbox project) | `HCLOUD_TOKEN` |
| `ansible/secrets/r2-devbox-state.age` | R2 access keys for the state bucket (env-file lines) | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

Bitwarden holds **only the age key** (plus provider account logins) — never the
tokens themselves. That's the hard rule in [secrets.md](secrets.md); don't drift.

**State** lives in Cloudflare R2: bucket `devbox-backup`, key
`terraform/devbox.tfstate` (S3 backend — see `backend.tf`). The bucket is
created **out-of-band** (bootstrap exception: it holds Terraform's own state),
EU jurisdiction, same Cloudflare account as `tipso-backup`. Every terraform
operation reads state from R2 and writes it back atomically — there is nothing
to sync or back up on a schedule; R2 *is* the single copy.

### Restoring on a new laptop

Nothing Terraform-specific to restore: once `secrets.local` is back
([secrets.md](secrets.md) → "Restoring on a new laptop") and the repo is cloned,
the creds are already there — encrypted, in git.

```bash
cd ~/_work/devbox
bin/devbox-tf init     # connects to R2 state
bin/devbox-tf plan     # expect: No changes
```

## One-time bootstrap (already done? skip)

1. **R2 bucket**: Cloudflare → R2 → Create bucket → `devbox-backup`,
   jurisdiction **EU**. Then *Manage R2 API tokens* → **Account API token**,
   scoped to this bucket only, **Object Read & Write**. Copy the S3 key pair
   (Access Key ID + Secret) — shown once.
2. **Hetzner token**: console.hetzner.cloud → devbox project → Security → API
   tokens → **Read & Write**. Copy — shown once.
3. **Encrypt both into the store** (on the laptop; recipe per
   [secrets.md](secrets.md) → "Adding a new encrypted secret"):

   ```bash
   cd ~/_work/devbox
   AGE_PUB=$(grep -o 'age1[0-9a-z]*' secrets.local | head -1)

   # Hetzner token (single line, no trailing newline)
   printf '%s' '<HETZNER_TOKEN>' | age -r "$AGE_PUB" -o ansible/secrets/hetzner-token.age

   # R2 state keys, env-file format
   age -r "$AGE_PUB" -o ansible/secrets/r2-devbox-state.age <<EOF
   AWS_ACCESS_KEY_ID=<R2_ACCESS_KEY_ID>
   AWS_SECRET_ACCESS_KEY=<R2_SECRET_ACCESS_KEY>
   EOF

   git add ansible/secrets/hetzner-token.age ansible/secrets/r2-devbox-state.age
   git commit -m "chore(secrets): add hetzner-token + r2-devbox-state" && git push
   ```

   Mind your shell history with inline secrets (`set +o history` first, or
   paste into the heredoc) — hygiene notes in [secrets.md](secrets.md).
4. **Adopt the running box** (no rebuild — import, don't recreate):

```bash
# ids: hcloud CLI or console URLs (server page, project Security page)
bin/devbox-tf init
bin/devbox-tf import hcloud_ssh_key.devbox    <ssh-key-id>
bin/devbox-tf import hcloud_server.devbox     <server-id>
bin/devbox-tf import hcloud_primary_ip.devbox <primary-ip-id>   # the box's existing IPv4
bin/devbox-tf plan
```

Iterate until `plan` shows changes **only** for: the new firewall (created +
attached) and the primary IP's `auto_delete → false`. Both are non-disruptive —
then `apply`. Importing the existing primary IP (rather than creating a new one)
is what keeps the current IP: it just becomes durable.

## Rebuild flow (replaces hetzner.md's old UI steps)

```bash
bin/devbox-tf destroy -target=hcloud_server.devbox   # old box gone; IP survives, detached
bin/devbox-tf apply                                  # new box, SAME IP
```

Then [provisioning.md](provisioning.md) §3 (Ansible) — `~/.ssh/config` and
`inventory.ini` are already correct because the IP didn't change. Clear the host
key once (`ssh-keygen -R <ip>`): a new box has a new host key even on the old IP.

`prevent_destroy` on the primary IP makes a bare `terraform destroy` fail —
that's intentional. Tearing down *everything* (leaving Hetzner) means commenting
the lifecycle block out first, deliberately.

## Day-to-day

| Task | How |
|---|---|
| Drift check | `bin/devbox-tf plan` (expect *No changes*) |
| Change server type / firewall / labels | edit `.tf`, `plan`, `apply` (a `server_type` change rescales **in-place**: brief poweroff, same IP/disk — but the disk grows irreversibly unless `keep_disk` is set) |
| Quality gate (CI runs the same) | `mise run tf:check` (fmt + validate, no creds needed) |
| Health check | `bin/doctor` (laptop) — includes a Terraform section |

## Things that go wrong

| Symptom | Fix |
|---|---|
| `init` fails with credentials error | R2 key stale/revoked — roll it in Cloudflare, re-encrypt `r2-devbox-state.age` (§ bootstrap step 3), commit |
| `Error: ... 401` from hcloud | Hetzner token revoked/expired — re-mint in console, re-encrypt `hetzner-token.age` (§ bootstrap step 3), commit |
| `devbox-tf` errors about `secrets.local` | You're not on the laptop, or it's not restored — [secrets.md](secrets.md) → "Restoring on a new laptop" |
| State lost / bucket deleted | Resources still run. Recreate bucket, `init`, re-`import` the three resources (§ bootstrap step 4) |
| `plan` wants to replace the server unexpectedly | A create-time attr changed (image, ssh key). Check `lifecycle.ignore_changes` in `server.tf`; don't apply until understood |
| Locked state (`.tflock`) after a crashed run | `bin/devbox-tf force-unlock <lock-id>` (id is in the error) |

Full incident matrix: [recovery.md](recovery.md).
