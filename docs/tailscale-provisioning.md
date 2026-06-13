# Tailscale device provisioning — tagged, zero-drift

How **every** device (the devbox, jarvis, any future box) gets onto the tailnet.
One pattern, no exceptions — so we never repeat the jarvis "joined personal-owned,
then hand-tagged in the console" drift.

> Sister docs: [`tailscale.md`](tailscale.md) (one-time tenant/account + the devbox's
> OAuth bootstrap), [`secrets.md`](secrets.md) (where the OAuth secret is encrypted).

## The rule

1. **Every device joins as a TAGGED node** — `tag:<device>` (e.g. `tag:devbox`,
   `tag:jarvis`). Tagged = owned by the *tailnet*, **no key expiry**, ACL-managed by
   tag. Servers must never be personal-owned (those expire ~90 days and need re-auth).
2. **The tag comes from a freshly-minted key, never from the console.** Hand-tagging
   a device via *Machines → Edit ACL tags* is **drift** — it doesn't survive a rebuild.
3. **No standing auth key, ever.** A per-device **OAuth client** mints a *fresh,
   single-use, preauthorized, tagged* key at each provision. Nothing long-lived to
   leak or expire.

Anything else is forbidden: a static auth key committed / in `tfvars`, a personal
(untagged) join, a manual console tag, or an OAuth secret/key stored as a Bitwarden
entry (Bitwarden holds only age keys + account logins — see [`secrets.md`](secrets.md)).

## Per-new-device setup (once)

1. **Define the tag** — admin console → **Access controls**, add to `tagOwners`:
   ```jsonc
   "tag:<device>": ["autogroup:admin"],
   ```
2. **Create the OAuth client** — admin → **Settings → OAuth → Generate OAuth client**:
   - **Scopes:** *Auth Keys → Write* only
   - **Tags:** `tag:<device>`
   - Copy the `client_id` (non-secret) + `client_secret` (`tskey-client-…`, shown once)
3. **Store the credentials** next to the device's owner:
   - `client_secret` → **age-encrypted**: the devbox in `ansible/secrets/tailscale-oauth.age`;
     a product repo in `<repo>/secrets/tailscale-oauth.age`.
   - `client_id` → **non-secret**, committed in plaintext (devbox: `ansible/group_vars/all.yml`
     `tailscale_oauth_client_id`; jarvis: a constant in `bin/jarvis-tf`).
4. Done. The role/wrapper mints keys from here on — no per-provision manual step.

## The two provisioning paths (pick by how the box is built)

### A. Ansible-provisioned (the devbox)

The `tailscale` role, on the controller, exchanges the OAuth client for an access
token, mints a fresh `tag:<device>` key, and runs `tailscale up`. Reference:
`ansible/roles/tailscale/tasks/main.yml` + [`tailscale.md`](tailscale.md) §6.

### B. Terraform / cloud-init-provisioned (jarvis)

The repo's TF wrapper (`bin/<repo>-tf`) mints the key **in memory** and injects it as
`TF_VAR_tailscale_authkey`; `cloud-init` then runs
`tailscale up --authkey=… --advertise-tags=tag:<device>` on first boot. Reference:
`jarvis/bin/jarvis-tf` + `jarvis/infra/terraform/cloud-init.yaml`.

The mint, in two API calls (what the wrapper/role does):
```bash
TOKEN=$(curl -fsS -d "client_id=$CLIENT_ID" -d "client_secret=$SECRET" \
  https://api.tailscale.com/api/v2/oauth/token | jq -r .access_token)
KEY=$(curl -fsS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d \
  '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":false,"preauthorized":true,"tags":["tag:<device>"]}}},"expirySeconds":600,"description":"<device>-provision"}' \
  https://api.tailscale.com/api/v2/tailnet/-/keys | jq -r .key)
```

## SSH over the tailnet — pick one, then drop public SSH

- **Tailscale SSH** (the devbox): `tailscale up --ssh` + an `ssh` stanza in the ACL
  (`src`/`dst`/`users`). Identity-based, no key distribution.
- **Plain key-SSH over the tailnet** (jarvis): no `--ssh`; reach the box at its tailnet
  IP with its SSH key. Needs no `ssh` ACL stanza, only base node connectivity.

Either way, once tailnet SSH is verified, **drop the public SSH firewall rule** so the
box has zero public attack surface.

## Verify & rotate

- **Verify:** `tailscale status` shows the device under **tagged-devices**;
  `tailscale whois <tailnet-ip>` shows `Tags: tag:<device>`.
- **Rotate the OAuth client** (compromise/loss): admin → Settings → OAuth → ⋮ →
  **Revoke** → create a fresh client → re-encrypt `tailscale-oauth.age` + update the
  committed `client_id`.
