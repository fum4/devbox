# Mobile setup

Set up the phone to drive agents on the devbox and test mobile apps via Tailscale. One-time per phone.

**End state**: Tailscale connected, Claude mobile app signed in with a live session for at least one project, Expo Go ready to load apps over the tailnet.

> Most steps in this doc are **on the phone** (App Store / iOS / Android UI). The few command-line bits are explicitly labeled **on the laptop** or **on the VPS**.

## Prerequisites

- iOS or Android phone
- Tailscale account ([tailscale.md](tailscale.md))
- Anthropic account with Claude Code access (Pro plan or higher)
- A running devbox VPS with a Claude session that has `/remote-control` enabled ([provisioning.md](provisioning.md))

## 1. Install Tailscale

App Store / Play Store → **Tailscale** → install → open → **Sign in** with the same account as your laptop/VPS → toggle the **VPN switch** to on.

Verify:

- Tap **Devices** in the app → you should see `devbox` (or `devbox-1`) and your laptop listed
- Try to load `http://<devbox-tailnet-ip>` in mobile Safari/Chrome — even if it 404s, a quick error means the connection works (a hang/timeout means Tailscale isn't routing)

iOS specifics:

- "Allow VPN configuration" prompt → Allow
- "Use Face ID for VPN" → optional
- The Tailscale tile appears in Control Center if you swipe down — handy for toggling

Android specifics:

- VPN permission prompt → Allow
- Battery optimization may kill background Tailscale on some manufacturers (Samsung, Xiaomi) — exclude Tailscale from battery saver if connections drop after the screen sleeps

## 2. Install the Claude mobile app

App Store / Play Store → **Claude** (Anthropic) → install → sign in with your Anthropic account (same as `/login` on the VPS).

Bottom navigation → **Code** tab. You'll see registered Remote Control sessions here.

For a session to appear:

1. The devbox must be running `claude` somewhere (inside the Zellij `claude` tab is the canonical place)
2. That session must have run `/remote-control` (which registers it with Anthropic's relay)

When both are true, the Code tab shows the session with a green dot. Tap it → you're driving the agent on the VPS from your phone.

If no sessions appear:

- **On the VPS** (via `ssh devbox` from the laptop): `zj <project>` → switch to the claude tab → if Claude isn't running, start it (`claude`).
- **Inside the Claude TUI**: `/remote-control` → choose "Enable Remote Control".
- **On the phone**: pull-to-refresh in the mobile app's Code tab.

## 3. Install Expo Go (only if working on mobile apps like kost)

App Store / Play Store → **Expo Go** → install. No login needed.

To connect to a Metro dev server running on the devbox:

1. **On the phone**: make sure Tailscale is ON.
2. **On the VPS**: make sure Metro is running (per the project's Zellij `mobile` tab, via `mise run mobile:dev` or similar).
3. **Option A — paste the URL** (on the phone): open Expo Go → there's an "Enter URL manually" field somewhere on the home screen → paste:
   ```
   exp://devbox:8081       (if MagicDNS resolves)
   exp://100.x.y.z:8081    (raw tailnet IP — get from `tailscale ip -4` on the VPS or from the Tailscale admin console)
   ```
4. **Option B — scan QR**: **on the laptop**, `ssh devbox`, then **on the VPS**: `zj <project>` and switch to the mobile tab. Metro's QR is printed there. **On the phone**, scan with the camera (Expo Go intercepts the URL).
5. **Option C — direct URL in Safari/Chrome on the phone**: type `exp://devbox:8081` → it'll offer to open in Expo Go → confirm.

The bundle takes 10-30 sec to download the first time, then the app launches.

### If Expo Go can't connect

- Tailscale OFF on the phone — toggle ON, retry.
- Metro using the wrong hostname — the per-repo `start:tailscale` script sets `REACT_NATIVE_PACKAGER_HOSTNAME` from `tailscale ip -4`. Check it's running.
- Phone and VPS on different tailnets (different Tailscale accounts) — they can't see each other.

## 4. (Optional) Codex mobile

OpenAI's Codex CLI has a mobile-driveable feature, but **it currently only pairs with a macOS host running the Codex desktop app**. Linux hosts (our VPS) are not supported as of 2026-05. Skip Codex mobile for now; the Claude app is the path on a Linux VPS.

If/when OpenAI ships Linux remote control: the Codex CLI is already installed on the VPS (per the playbook), and skills/AGENTS.md are shared between Claude and Codex. Just pair the mobile app and go.

## What you DON'T need on the phone

- A terminal app — you don't SSH from the phone in this workflow; agents do the work and you drive them from the Claude app
- A code editor — same reason
- GitHub mobile — useful for merging PRs (since `wt merge` can also be triggered via the agent), but not required

## Recovery if the phone setup gets borked

- **Claude session disappears**: **on the phone**, open Claude app → Code tab → if the list is empty, the VPS-side `/remote-control` got terminated. To re-enable: **on the laptop**, `ssh devbox` → **on the VPS**, `zj <project>` → claude tab → **inside the Claude TUI**, `/remote-control`.
- **Tailscale dropped**: toggle the VPN off + on. If still broken, sign out + sign back in.
- **Phone lost / replaced**: reinstall Tailscale (sign in, same account) + Claude (sign in, same account) + Expo Go. Nothing on the phone is irreplaceable — all state lives on the VPS.

## Tips

- **Pin the Claude app** somewhere easy on your home screen. The Code tab is the main driver interface.
- **Use Tailscale's "Mullvad on-demand" sparingly**. Auto-toggling Tailscale based on Wi-Fi networks is brittle; leave it on always.
- **Add `exp://devbox:8081` as a Safari bookmark** for the kost workspace — one tap to launch the app via Expo Go.
- **Voice input**: the Claude app supports dictation. For long-form agent prompts on the go, this is faster than typing.
