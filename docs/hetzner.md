# Hetzner Cloud setup

How to set up a Hetzner Cloud account so you can rent a VPS for the devbox. One-time per Hetzner account (rarely changes). For *creating individual VPSes*, see [provisioning.md](provisioning.md).

**End state**: Hetzner Cloud account with verified identity, payment method on file, a project named `dev`, your laptop's SSH public key uploaded under Security.

## Prerequisites

- Laptop set up per [laptop.md](laptop.md) (you need the SSH public key at `~/.ssh/id_ed25519_devbox_hetzner.pub`)
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

## 4. Upload the laptop's SSH public key

This is what lets your laptop log in to any VPS you create in this project.

On the laptop:

```bash
pbcopy < ~/.ssh/id_ed25519_devbox_hetzner.pub
```

In Hetzner Console (inside the `dev` project) → sidebar → **Security** → **SSH Keys** tab → **Add SSH Key**:

- **Public Key**: paste (Cmd+V)
- **Name**: `laptop-vps` (or `laptop` — anything memorable)
- **Add SSH Key**

The key now shows in the list with its fingerprint. Every future VPS you create can tick this key during the create-server form, and you'll be able to `ssh root@<new-ip>` immediately.

## 5. Don't create a VPS yet

VPS creation is per-rebuild and lives in [provisioning.md](provisioning.md). Stopping here keeps "Hetzner account setup" cleanly separate from "rent a machine."

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

- **Bigger VPS needed**: stop server → change type to CPX32 or CCX13 → start. Same IP, same disk, ~1 min downtime. Hetzner Console → server detail page → ⋮ → **Rescale**.
- **Move regions**: not really — the IPs are region-bound. Easier to delete + recreate in the new region.
- **Need a second VPS** (staging, side-project): create another in the same project. The SSH key from step 4 is already there; just tick it.
