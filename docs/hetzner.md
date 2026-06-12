# Hetzner Cloud setup

The Hetzner-UI parts that **stay manual**: account setup (one-time per account, sections 1–3) and the API token Terraform authenticates with (section 4). Creating/destroying the VPS itself is **no longer a UI flow** — it's Terraform (section 5 → [terraform.md](terraform.md)). Provider-specific knowledge stays in this one file; the post-create configuration flow lives in [provisioning.md](provisioning.md).

**End state after sections 1–4**: account verified, payment on file, project `dev` exists, an API token for that project age-encrypted at `ansible/secrets/hetzner-token.age`. From there, section 5 is one command.

## Prerequisites

- Laptop set up per [laptop.md](laptop.md) (you need the SSH public key at `~/.ssh/devbox_vps.pub`)
- A payment card (personal or company)
- ID / passport image for identity verification

## 1. Sign up

https://accounts.hetzner.com/signUp

Pick **Personal** OR **Business** account type:

- **Personal**: simpler, invoice is in your name. Good if you pay personally.
- **Business**: invoice is in the company's name, supports VAT ID, deductible as business expense.

Fill the form with real details — Hetzner verifies against payment + (sometimes) ID.

### VAT ID (if Business + EU-registered)

If your business is registered for VAT, enter your VAT ID under **Billing → Tax info** (or similar, depending on UI version). For Romania, format is `RO<CUI>` (e.g. `RO12345678`).

With a valid VAT ID, Hetzner doesn't charge German VAT (EU reverse-charge rule). Without it, ~19% VAT is added.

If you can't find the field at signup time, skip it — add it under **Billing → VAT/Tax info** later, before the first invoice cycles.

### Identity verification

Hetzner typically asks for an ID upload (passport / national ID photo) or a credit-card auth. Can take minutes to hours. **You can't create VPSes until this is approved.**

## 2. Add a payment method

Hetzner Console → **Billing** → **Payment method** → add a card.

Verify with the small auth charge if asked.

## 3. Create a Cloud project

Once verified, go to https://console.hetzner.cloud — you land on the *Projects* view.

Click **New Project** (top right). Name it `dev` (or whatever). Click into the project.

Each project is a billing + access boundary. One project for the devbox is enough.

## 4. Create an API token for Terraform

This is what lets Terraform manage servers in this project — the one credential the UI must mint (a token can't create itself).

Hetzner Console → your project → sidebar → **Security** → **API tokens** → **Generate API token**:

- **Description**: `devbox-terraform`
- **Permissions**: **Read & Write**

Copy the token (shown once) and **age-encrypt it into the store** as `ansible/secrets/hetzner-token.age` — exact recipe in [terraform.md](terraform.md) → "One-time bootstrap" step 3. It does **not** go into Bitwarden or any plaintext file ([secrets.md](secrets.md) → the hard rule under "The two lanes of secrets").

(The laptop's SSH key no longer needs manual uploading — Terraform registers `~/.ssh/devbox_vps.pub` as an `hcloud_ssh_key` resource.)

## 5. Create / destroy the VPS — via Terraform

The server, its **stable primary IP**, the cloud firewall, and the SSH-key registration are all `terraform/devbox/` resources. The full runbook (bootstrap, adopting a running box, rebuild flow) is [terraform.md](terraform.md); the short version:

```bash
bin/devbox-tf apply                                  # create (or reconcile) the box
bin/devbox-tf destroy -target=hcloud_server.devbox   # destroy ONLY the server; the IP survives
```

The decisions the old UI form asked for are now code (`terraform/devbox/variables.tf`): Helsinki (hel1), Debian 12, CX33, name `devbox`, backups off. Because the primary IP outlives the server, a rebuild keeps the same IPv4 — no more copying IPs into config files ([provisioning.md](provisioning.md) §2 is now a no-op).

Billing stops at the second of server deletion. A detached primary IP costs ~€0.50/mo while no server is attached (free while attached). Snapshots taken beforehand persist (~€0.0119/GB/month) until deleted separately.

## Recurring costs

The devbox runs on **CX33** (Helsinki):

| | Cost |
|---|---|
| CX33 (4 vCPU AMD, 8 GB RAM, 80 GB disk) | €6.49/mo |
| Public IPv4 (included) | — |
| Public IPv6 (included) | — |
| Bandwidth (20 TB included) | — |
| Backups (optional, +20%) | +€1.30/mo if enabled |
| Snapshots (when held) | ~€0.0119/GB/month (so ~€1/month while holding) |

Hetzner bills **hourly, prorated**. Deleting a VPS stops billing immediately. So nuking + recreating during a rebuild costs cents.

## Tips for the UI

- **Project picker** is top-left. If you've got multiple projects, double-check you're in the right one before clicking destructive actions.
- The **⋮** menu on a server gives delete, snapshot, rebuild-from-image, rescue-mode.
- **Activity** (sidebar) is your audit log — useful when "did I delete that?" questions arise.

## What you DON'T set up on Hetzner

- DNS (we use Tailscale MagicDNS; no public hostname needed)
- Load balancers (out of scope for a personal dev box)
- Volumes / object storage (the VPS's local 80GB is enough)
- Backups (snapshots on-demand are sufficient for our use case)

## When to revisit Hetzner

- **Bigger VPS needed**: change `server_type` in `terraform/devbox/variables.tf` → `bin/devbox-tf apply` (in-place rescale: brief poweroff, same IP + disk; the disk grows irreversibly unless you set `keep_disk`). Avoid rescaling via the console — that's drift the next `plan` will fight.
- **Move regions**: not really — the IPs are region-bound. Easier to delete + recreate in the new region (a `location` change forces replacement, and the primary IP can't follow).
- **Need a second VPS** (staging, side-project): per the cross-repo rule ([secrets.md](secrets.md) → "Global doctrine"), that machine's repo brings its own Terraform + state bucket — don't add it to `terraform/devbox/`. Same Hetzner project is fine; mint it its own API token.
