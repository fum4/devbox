---
name: sessions
description: Full inventory of what's live on the box — every Claude session (with a one-line gist of what it's about), every git worktree, and the dev-server stacks. Trigger on "/sessions", "/status", "what sessions are running", "what's running", "status check", "lay of the land", "what am I working on where", or as step 2 of the session-start ritual. Say "quick" to skip the transcript gists.
---

# /sessions — sessions + worktrees + dev servers, with context

One skill, the whole picture: agent sessions (each with a one-line "what it's
about"), worktrees, and dev-server stacks. The gist comes from the actual
transcript — **do not trust the session name**; names lie (a tab named
`wishlist-audit` once did `ui-fixes` work).

## Steps

1. **Get the facts:** run `claude-sessions`. It prints every known agent session
   (name, state — active/stopped/failed, last-active, cwd[branch], conversation
   id), any *unmanaged* stray claude processes, and every worktree (branch,
   which session is in it, uncommitted count). It's systemd-driven, so it lists
   stopped/parked sessions too (recoverable with `claude-restore <name>`).
   After a reboot, surface any restorable sessions ("N sessions stopped —
   `claude-restore` to bring them back").

2. **Dev-server stacks** — list running process-compose stacks (the dev
   servers, under `/serve`):
   ```bash
   ls "$XDG_RUNTIME_DIR"/pc-*.sock 2>/dev/null
   ```
   The project is the `pc-<name>.sock` stem; for the process list,
   `process-compose process list -U -u <sock>`. Glance at `ss -tlnp` for bound
   dev ports if it adds signal.

3. **Add a one-line gist per session — read cheaply, don't deep-analyze.**
   For each session with a resolvable transcript at
   `~/.claude/projects/<cwd-with-slashes-as-dashes>/<sessionId>.jsonl`:
   - Skim the *recent* turns only — e.g. `jq` the last few `type=="user"`
     messages, or read the tail. You're after "what is this session about,"
     not a full summary. **One line each.**
   - No transcript yet (fresh, never used) → "not started yet", don't guess.

   **Skip this step when the user asked for a quick look** ("quick", "at a
   glance", "/status") — render the inventory without gists instead of making
   them wait.

4. **Present a compact combined view**, three sections:
   - **Sessions:** `name · state · last-active · cwd[branch] · «gist»`. Call
     out `failed` (a crash that exhausted restarts) and `unmanaged` (a hand-run
     claude not under systemd) entries.
   - **Worktrees:** path, branch, live-session, uncommitted flag — highlight
     any with **uncommitted work** or **no live session** (those deserve
     attention; `/prune` is the cleanup path).
   - **Dev stacks:** `<name>` + ports bound (or "none up").

5. **Flag drift if it's obvious** — only what pops out of this read-out itself:
   a failed unit, an unmanaged process (re-spawnable via `claude-spawn`), a
   worktree with no live session and a merged PR. Don't go hunting.

## Rules

- **Read-only.** Never close, kill, park, stop, or prune anything. Cleanup is
  `/prune` (batch) or `/park` & `/kill` (single session).
- Recover a session with **`claude-restore <name>`** (or attach live via
  `dtach -a $XDG_RUNTIME_DIR/claude-<name>.sock`), never a raw
  `claude --resume` — the systemd unit owns the conversation id.
- Zellij dashboards (`zj <project>`) are disposable views, not where work
  lives — not part of the inventory. If asked, `zellij ls`.
- Keep the whole output skimmable on one screen — tables and short lines.
