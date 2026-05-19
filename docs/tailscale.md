# Tailscale setup

Tailscale is the **private mesh network** between your phone, laptop, and the devbox VPS. No public ports for dev servers, no DNS to manage, works across cafés / cellular / hotel Wi-Fi.

One-time per Tailscale account (rarely changes). For *generating an auth key for a fresh VPS provision*, see [rebuild.md](rebuild.md).

**End state**: Tailscale account, MagicDNS enabled, phone + laptop joined to the tailnet.

## Prerequisites

- Any browser (account signup is OAuth — use Google for simplest)

## 1. Sign up

https://login.tailscale.com/start

Choose **Sign in with Google** (or whichever provider you prefer). The Tailscale tenant (called a "tailnet") is created automatically from your account.

Free tier covers:

- 100 devices
- 3 users
- All core features (MagicDNS, SSH, Funnel, ACLs)

For personal use this is generous and won't expire.

## 2. Enable MagicDNS

Open https://login.tailscale.com/admin/dns → scroll to **MagicDNS** → toggle **Enable MagicDNS**.

After this, every device on your tailnet gets a hostname. From any tailnet device:

```
ssh devbox-1                          # short name
ssh devbox-1.tail-something.ts.net    # full FQDN
```

Both resolve to the device's tailnet IP (`100.x.y.z`). Way easier than memorizing IPs.

**You can rename a machine** in https://login.tailscale.com/admin/machines → click ⋮ on a row → **Edit machine name**. e.g. rename `devbox-1` → `devbox` to match your `Host devbox` SSH alias.

## 3. Install Tailscale on the laptop

```bash
brew install --cask tailscale
```

Launch the Tailscale app (it lives in the macOS menu bar). Click the icon → **Log in**. The auth flow opens a browser — accept.

Once logged in, the menu bar shows your laptop's tailnet IP. Verify:

```bash
tailscale ip -4
# 100.x.y.z
```

## 4. Install Tailscale on the phone

App Store / Play Store → search **Tailscale** → install → sign in (same account as step 1) → toggle the VPN on. The phone now has a tailnet IP too.

Phone-side details and the rest of the mobile setup live in [mobile.md](mobile.md).

## 5. The devbox VPS

The VPS gets onto the tailnet via the `tailscale` Ansible role during provisioning — see [rebuild.md](rebuild.md). You generate a one-shot auth key, pass it via `TAILSCALE_AUTHKEY` env var, the playbook does the rest.

## Auth keys — how they work and when to use which

Auth keys are **pre-authorization tokens**: a machine that presents a valid auth key joins the tailnet without browser interaction. Useful for unattended Ansible runs.

Generate one at https://login.tailscale.com/admin/settings/keys.

| Option | Effect | When to use |
|---|---|---|
| **Description** | Free text | Always — name it after where it's being used (`devbox-rebuild-2026-05-20`) |
| **Reusable** | One key can authorize multiple devices | Don't use for VPS provisioning — one-shot is safer |
| **Ephemeral** | Device auto-removes from tailnet on disconnect | Off for VPSes (they should persist) |
| **Pre-approved** | Device joins without manual approval | Default ON if your tailnet has device approval enabled |
| **Tags** | ACL group membership | Leave empty for personal use |
| **Expiration** | Key auto-revokes | 1 day is fine for a single provision |

Keys are *consumed on use* (when non-reusable). You don't need to revoke afterwards — it's already dead.

## Tailscale SSH

Tailscale also offers an SSH layer that uses tailnet identity instead of traditional SSH keys. Our devbox uses `tailscale up --ssh` (the playbook sets this), which means:

- Other tailnet members can `ssh fum4@devbox` via Tailscale SSH (auth via Tailscale ACL)
- Traditional SSH (port 22 + key) still works in parallel — preferred for now

You don't have to configure anything on the laptop side to use Tailscale SSH; if the VPS has it enabled, just `ssh devbox` works (and Tailscale negotiates auth invisibly when the source is a tailnet member).

## Funnel (for later)

Tailscale Funnel exposes a tailnet service publicly at `<host>.<tailnet>.ts.net` with a real TLS cert. We don't need it now (no public services), but it's the planned mechanism for future webhook receivers — see [`docs/decisions/0002-agent-trigger-architecture.md`](decisions/0002-agent-trigger-architecture.md) if it exists.

## Things to NOT do

- **Don't run Tailscale on the laptop on a different account from the phone/VPS** — devices on different tailnets can't see each other.
- **Don't share auth keys**. They're powerful (a stolen key = stranger joins your tailnet). Treat like passwords; rotate immediately if leaked.
- **Don't configure ACLs** at this scale — the default "anyone in the tailnet can reach anyone" is fine for one user.

## When to revisit Tailscale

- **Add a new device** (work laptop, secondary phone): install Tailscale, sign in, done.
- **Rename a machine** (e.g., the auto-generated `devbox-1` → `devbox`): admin console → machines → rename.
- **Audit access**: admin console → Machines tab shows everything that's ever connected. Remove anything you don't recognize.
- **Tailnet outage** (rare): https://status.tailscale.com.
