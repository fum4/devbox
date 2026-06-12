# Session hosting — agents & dev servers

> **Status: IMPLEMENTED — migration of existing sessions pending.** The roles,
> units, and helpers below are in place and tested (spawn / crash-restart /
> resume / clean-stop / restore all verified). Sessions spawned from now on use
> this model. Agent sessions that predate it still run as unmanaged processes in
> the old per-project Zellij servers until migrated — `claude-sessions` flags
> those as `unmanaged`. See [§ Migration](#migration) for the cutover.

How long-lived processes on the devbox are kept alive, isolated, reachable from
the phone, and viewable from the laptop. This is the contract behind `/sessions`,
`/status`, `/serve`, `claude-spawn`, and `zj`.

## The problem this solves

A project workspace today is a single Zellij session (`zj kost`) whose tabs run
**two completely different kinds of process**:

- **Agent sessions** — `claude --remote-control <name>` TUIs, driven from the
  phone. Each is a *stateful conversation* you never want to lose.
- **Dev servers** — `mise run api:dev`, `mise run mobile:dev`, docker infra.
  *Stateless*, port-bound, restarted constantly during development.

Zellij is the **single owner of both**, and that's the bug. A Zellij *server* is
a shared fate domain: when it dies, every process in every tab dies with it, and
"resurrecting" the session only rebuilds the *tab layout* — the processes inside
are gone. Resurrection re-runs the layout commands fresh, which is *correct* for
`api:dev` (you want it fresh) but *wrong* for `claude` (you get a brand-new agent,
not your resumed conversation).

This actually happened: on 2026-06-09 the `kost` Zellij server had been dead for
~6h. Six agent sessions (`reports`, `cost-grouping`, `social-bots`,
`e2e-research`, …) and the dev servers were all silently down. Only the
transcripts on disk survived. One point of failure took out the lot.

The two process kinds have **opposite lifecycle needs**, so they need **different
owners**:

| | Agent session | Dev servers (Metro/API/infra) |
|---|---|---|
| State | Stateful — a conversation | Stateless |
| On death, you want | **Preserve / resume** the exact process | **Restart fresh** |
| Scope | Per session | Per **worktree**, port-bound |
| Driven by | Phone (Remote Control) | Tailscale clients hitting the port |
| Lifecycle | Long — survives reboots; resume on demand | On-demand — up while developing |
| Owner (target) | **systemd + dtach** | **process-compose**, via `/serve` |

## Principles

1. **systemd owns lifecycle; the multiplexer is a disposable view.** Long-lived
   processes are supervised by the OS (the thing built for it), not by a terminal
   UI. Zellij becomes a *window* onto them — if it dies, nothing stateful is lost.
2. **One supervised unit per agent session — no shared fate.** One crashing or
   OOMing agent can't take down the others.
3. **Agents and dev servers never share a supervisor.** Reloading Metro must
   never touch an agent, and vice-versa.
4. **mise is orthogonal.** It supplies per-project tool versions + env + tasks
   and runs identically whether launched from a Zellij pane, a systemd
   `ExecStart`, a dtach socket, or process-compose. It constrains none of this.

## Architecture

### Agent sessions → systemd user units + dtach

Each agent session is a **templated systemd *user* unit**, `claude@<name>.service`,
under a shared `claude.slice` that caps aggregate memory/CPU so no runaway agent
can starve the box.

`loginctl enable-linger fum4` (**already set** on the box) means the user manager
runs at boot independent of any login — so units survive SSH drops, laptop sleep,
and reboots-of-the-box.

A Claude session is a TUI and needs a real pty even when nobody is watching.
**[dtach](https://github.com/crigler/dtach)** provides exactly that: a detachable
pty with **no server** (unlike tmux, which would re-introduce a shared fate
domain). dtach runs in the unit's foreground (`-N`) as the unit's main process;
`claude` is its child in a genuine pty.

```ini
# ~/.config/systemd/user/claude@.service   (chezmoi-managed)
[Unit]
Description=Claude agent session: %i

[Service]
Slice=claude.slice
# Per-session knobs (CWD, RESUME, EXTRA_ARGS) written by claude-spawn before start:
EnvironmentFile=%h/.config/claude-sessions/%i.env
# dtach holds the pty (foreground, -N) as the unit's main process; the launcher
# is its child, and `claude` the grandchild — in a genuine pty.
ExecStart=/usr/bin/dtach -N %t/claude-%i.sock %h/.local/bin/claude-session-run %i
# Resume-same on crash: the launcher re-attaches to the pinned SESSION_ID, so a
# crashed agent comes back as the *same* conversation (see Resolved decision 1).
Restart=on-failure
RestartSec=2
# Per-agent soft cap: throttle one bloated session before it pressures siblings.
# (A 1M-context Opus session can be heavy; this reclaims/swaps rather than kills.)
MemoryHigh=3G

[Install]
WantedBy=default.target
```

```ini
# ~/.config/systemd/user/claude.slice   (chezmoi-managed)
[Slice]
# 15 GB box. Ceilings, not reservations — idle agents sit at a few hundred MB;
# these only bite under sprawl. Leaves headroom for on-demand dev servers, which
# already auto-size off *available* RAM (see kost's e2e:parallel task).
MemoryAccounting=yes
MemoryHigh=10G        # soft: reclaim/swap pressure kicks in
MemoryMax=12G         # hard: OOM-kill within the slice before the box is threatened
CPUWeight=100         # default; the agent is what the user drives — don't starve it
```

The launcher exists because systemd can't read `WorkingDirectory` or per-instance
args out of an `EnvironmentFile` — so a tiny chezmoi-managed script does it, and
`bash -ic` ensures the mise shell hook fires (PATH picks up `~/.local/bin`):

```bash
# ~/.local/bin/claude-session-run <name>   (chezmoi-managed)
#!/usr/bin/env bash
set -euo pipefail
# SESSION_ID / CWD / PERM_MODE / EXTRA_ARGS come from the EnvironmentFile.
cd "$CWD"
# Pin the conversation to a stable UUID. First launch creates it (--session-id);
# any relaunch (crash-restart, or a deliberate restore) resumes that exact id.
transcript="$HOME/.claude/projects/${CWD//\//-}/$SESSION_ID.jsonl"
if [[ -f "$transcript" ]]; then id_flag=(--resume "$SESSION_ID")
else                            id_flag=(--session-id "$SESSION_ID"); fi
exec bash -ic 'exec claude --remote-control "$1" "${@:2}" \
  --permission-mode "${PERM_MODE:-bypassPermissions}" $EXTRA_ARGS' \
  _ "$1" "${id_flag[@]}"
```

`claude-spawn` generates a fresh UUID at spawn and writes it as `SESSION_ID` in
the env file (or, for "resume this existing conversation", writes the existing
id — e.g. `49281bed-…`). Either way the unit is restart-safe and the conversation
key is durable.

- **Spawn from anywhere:** `claude-spawn` writes `~/.config/claude-sessions/<name>.env`
  then `systemctl --user start claude@<name>`. No "must be inside Zellij"
  constraint, no headless-resurrect hack.
- **Remote Control is unchanged:** the phone connects to the supervised `claude`
  process by its `--remote-control` name regardless of who (if anyone) is attached.
- **Attach from the laptop:** `dtach -a $XDG_RUNTIME_DIR/claude-<name>.sock`
  (detach with `Ctrl-\`). The Zellij dashboard does this for you (below).
- **Logs:** `journalctl --user -u claude@<name>` — survives even when the window
  is closed.

### Dev servers → process-compose, on-demand

Dev servers are **on-demand and restart-fresh** (the chosen model — they're not
kept always-on). Each project gets a `process-compose.yaml` describing its stack
(infra → API → Metro), and the **`/serve` skill** drives it:
`process-compose up -D` to start detached, `process-compose down` to stop,
`process-compose attach` for the live TUI. Port/worktree-conflict handling stays
in `/serve` exactly as today.

These are *not* `enabled` at boot and get no restart policy — you bring them up
when developing. Because they live in their own process-compose project, killing
or reloading a dev server never touches an agent.

> **PTY note.** The existing `process-compose` role warns it's for headless
> services because Metro/Claude want a pty. process-compose can allocate one per
> process (`is_tty: true`); Metro's interactive console (`r` to reload, etc.) is
> rarely needed on the devbox since the phone hits Metro over Tailscale. If a
> given dev server genuinely needs interactive keys, wrap that one process in
> dtach inside the stack. Decide per project.

### Zellij → disposable per-project dashboard

`zj <project>` generates a Zellij layout that is **pure view**:

- one tab per live agent session for that project → `dtach -a <socket>`
- one tab → `process-compose attach` for the dev-server stack
- a plain `shell` tab

Nothing stateful lives in Zellij anymore. Kill it, restart it, never start it —
the agents and servers keep running under their real owners. Zellij is launched
interactively when you attach from the laptop; it does **not** need to be
supervised or survive anything.

## Session lifecycle: spawn → park / restore → kill

Four helpers own the lifecycle; the matching skills add the judgment layer
(WIP checks + user confirmation) on top:

| Operation | Command | Effect | Reversible? |
|---|---|---|---|
| Spawn | `claude-spawn --name <n> --cwd <d>` | unit started, fresh conversation id pinned in `<n>.env` | — |
| Park | `claude-park <n>` (judgment: `/park`) | unit stopped; env file + conversation **kept**; logged to `~/.claude/parked-sessions.log` | yes — `claude-restore <n>` |
| Restore | `claude-restore <n>` | unit started again, resumes the *exact* pinned conversation | — |
| Kill | `claude-kill <n> [--rm-worktree] [--force]` (judgment: `/kill`) | unit stopped; session **forgotten** (env file removed — leaves `claude-restore`); optionally removes the cwd *if it's a linked worktree* (+ local branch); logged to `~/.claude/killed-sessions.log` | partially — transcript survives in `~/.claude/projects/`; resurrect via `claude-spawn --resume <id>` (id is in the kill log). The worktree + uncommitted work are gone for real. |

Guard rails built into `claude-kill`:

- **A main checkout is never removed** — `--rm-worktree` only acts when the cwd
  is a *linked* worktree (`--git-dir` ≠ `--git-common-dir`).
- **Self-kill is safe**: invoked from inside the session being killed (the
  `/kill` skill's normal case), it re-execs into a transient systemd unit so the
  cleanup survives the caller's own death.
- **Log first, act second** (same as `claude-park`): the kill log line with the
  resurrect command is written before anything stops.

The `/park` and `/kill` skills surface in-flight work (uncommitted changes,
unpushed commits, open PRs) and re-ask before acting — use them rather than the
raw helpers when driving by chat. `/prune` is the batch flavor for cleanup
across many worktrees/sessions.

## What changes in the repo

| Area | Change |
|---|---|
| `ansible/roles/dtach/` (new) | Install `dtach` (apt). Add to `site.yml` under `tools`. |
| `chezmoi/.../systemd/user/claude@.service` (new) | The templated unit + `claude.slice`. Applied by the `dotfiles` role. |
| `ansible/roles/claude/` | `loginctl enable-linger` + ensure `~/.config/claude-sessions/` exists (session-hosting prerequisites live with the claude install). |
| `claude-spawn` | Rewrite: write per-session env file → `systemctl --user start claude@<name>`. Drop the "inside Zellij" requirement and the new-tab plumbing. |
| `claude-sessions` | Rewrite enumeration: `systemctl --user list-units 'claude@*'` as truth (+ journald/transcript for the gist), instead of `pgrep`/`/proc` scraping. |
| `zj` | Rewrite: generate the dashboard layout (dtach-attach agents + `process-compose attach`). |
| `/serve` skill | Point at each project's `process-compose.yaml`. |
| `/sessions`, `/status`, `/prune`, `/new-chat-session`, `/new-work-session` | Update to the systemd model (start/stop/park = unit operations; "park" records the resume id and `stop`s the unit). |
| Per-project `process-compose.yaml` (new, per repo) | Describe the dev-server stack (wrap existing `mise run` tasks). Start with kost. |
| `agents/AGENTS.md` | Replace "long-running processes go in Zellij" with this model; link here. |
| `docs/README.md`, `docs/recovery.md` | Index this doc; add session symptoms (agent unit dead, socket stale, dashboard won't attach). |

## Resolved decisions

1. **Crash-restart = resume-same.** `Restart=on-failure`; the launcher re-attaches
   to the agent's pinned `SESSION_ID`, so a crashed agent comes back as the *same*
   conversation, not a blank one. Made deterministic by `claude --session-id <uuid>`
   (pin at first launch) → `--resume <uuid>` (every relaunch). No transcript
   scraping. (Resume reconstructs context and waits for input — it does **not**
   auto-continue work.)
2. **`claude.slice` limits (15 GB box):** per-agent `MemoryHigh=3G` (soft),
   slice `MemoryHigh=10G` / `MemoryMax=12G`, `CPUWeight=100`. These are *ceilings*,
   not reservations — idle agents use a few hundred MB, so the caps only bite under
   sprawl, and on-demand dev servers (which auto-size off available RAM) keep their
   headroom. Starting values; tune by observation.
3. **One-name invariant.** A session has *one* human-facing name used in three
   places: the systemd instance (`claude@<name>`), the Remote-Control name
   (`--remote-control <name>`, what the phone shows), and the dashboard tab. The
   env file is `<name>.env`. The durable *conversation* key is a separate stable
   UUID (`SESSION_ID`) inside that env file. So the name can never drift between
   what the phone shows, what `/sessions` lists, and what the unit is — while the
   UUID guarantees a restart resumes the exact conversation. `zj` maps project →
   agent units by the `CWD` recorded in each env file.
4. **Boot policy = explicit restore (proposed).** Agent units are **not** enabled
   at boot. Rationale: across SSH drops, laptop sleep, and a dead Zellij viewer
   the agent *process never dies* — that's now seamless. A full box reboot is the
   one case where the process necessarily dies, and reboots are rare and usually
   deliberate (`devbox-reprov`, kernel update). Auto-resuming a fleet of agents at
   boot risks (a) a memory stampede as several large contexts reload at once and
   (b) an agent that was mid-tool-loop resuming unattended under
   `bypassPermissions`. Instead, a **`claude-restore`** helper lists the sessions
   that were live before the reboot (from their persisted env files) and resumes
   all / a selected subset on demand — surfaced by the session-start ritual
   (`/sessions` notes "N sessions were live before the last reboot →
   `claude-restore`"). One deliberate command, full visibility, no stampede.
   *Open for your call: this, or true auto-restore-on-boot.*

## Migration

1. Land `dtach` role + the unit/slice + `claude-spawn`/`claude-sessions`/`zj`
   rewrites behind the new model; `devbox-reprov --tags …` + `chezmoi apply`.
2. Author `kost/process-compose.yaml` from its `mise` `dev`/`infra:up`/`api:dev`/
   `mobile:dev` tasks; switch `/serve` to it.
3. Migrate the live `kost` Zellij tabs: each agent tab → `claude@<name>.service`
   (the currently-live `e2e-tests`, resuming `49281bed-…`; the rest resume from
   their transcripts as needed). Dev-server tabs → the process-compose stack.
4. Verify: kill the Zellij viewer → confirm agents + servers keep running and the
   phone still reaches them; reboot the box → confirm the manager comes back and
   sessions are re-attachable/resumable.
5. Roll the same `process-compose.yaml` pattern to the other repos.
