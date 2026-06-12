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

> All commands run **on the laptop** — the lane-2 credentials live there
> exclusively, and a dead box can't rebuild itself. Use the **`bin/devbox-tf`**
> wrapper, which loads the R2 state creds and forwards to `terraform`.

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

## Credentials (lane 2) and state

Two gitignored files in `terraform/devbox/`, both mode 0600, both backed up in
**Bitwarden** (see [secrets.md](secrets.md) → "The two lanes of secrets" — these
are *laptop-only TF creds*, not age-store material):

| File | Holds | Bitwarden entry |
|---|---|---|
| `terraform.tfvars` | Hetzner API token (R/W, devbox project) | *"devbox Hetzner API token"* |
| `.r2-backend.env` | R2 access keys for the state bucket | *"devbox-backup R2 access keys"* |

**State** lives in Cloudflare R2: bucket `devbox-backup`, key
`terraform/devbox.tfstate` (S3 backend — see `backend.tf`). The bucket is
created **out-of-band** (bootstrap exception: it holds Terraform's own state),
EU jurisdiction, same Cloudflare account as `tipso-backup`.

### Restoring on a new laptop

```bash
cd ~/_work/devbox/terraform/devbox
cp terraform.tfvars.example terraform.tfvars && chmod 600 terraform.tfvars
cp .r2-backend.env.example .r2-backend.env   && chmod 600 .r2-backend.env
# fill both from Bitwarden, then:
../../bin/devbox-tf init     # connects to R2 state
../../bin/devbox-tf plan     # expect: No changes
```

## One-time bootstrap (already done? skip)

1. **R2 bucket**: Cloudflare → R2 → Create bucket → `devbox-backup`,
   jurisdiction **EU**. Then *Manage API tokens* → token scoped to this bucket,
   **Object Read & Write** → keys into `.r2-backend.env` + Bitwarden.
2. **Hetzner token**: console.hetzner.cloud → devbox project → Security → API
   tokens → **Read & Write** → into `terraform.tfvars` + Bitwarden.
3. **Adopt the running box** (no rebuild — import, don't recreate):

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
| `init` fails with credentials error | `.r2-backend.env` missing/stale — restore from Bitwarden |
| `Error: ... 401` from hcloud | Hetzner token revoked/expired — re-mint in console, update `terraform.tfvars` + Bitwarden |
| State lost / bucket deleted | Resources still run. Recreate bucket, `init`, re-`import` the three resources (§ bootstrap step 3) |
| `plan` wants to replace the server unexpectedly | A create-time attr changed (image, ssh key). Check `lifecycle.ignore_changes` in `server.tf`; don't apply until understood |
| Locked state (`.tflock`) after a crashed run | `bin/devbox-tf force-unlock <lock-id>` (id is in the error) |

Full incident matrix: [recovery.md](recovery.md).
