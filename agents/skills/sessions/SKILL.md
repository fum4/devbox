---
name: sessions
description: List every active Claude session and git worktree with a one-line gist of what each is about. Trigger on "/sessions", "what sessions are running", "show me my sessions", "what am I working on where", or as step 2 of the session-start ritual. The gist comes from the actual transcript, never the session name.
---

# /sessions — active session + worktree inventory

Show the user, at a glance, every live Claude session and git worktree, each with a one-line "what it's about" so they can remember or pick up context.

**Do not trust the session name.** Names lie — a tab named `wishlist-audit` ended up doing `ui-fixes` work. Derive the gist from the transcript.

## Steps

1. **Get the facts:** run `claude-sessions`. It prints every known agent session (name, state — active/stopped/failed, last-active, cwd[branch], conversation id), any *unmanaged* stray claude processes, and every worktree (branch, which session is in it, uncommitted count). It's systemd-driven: sessions are `claude@<name>.service` units with a persisted env file, so it lists stopped/parked sessions too (which `claude-restore <name>` brings back). After a reboot, surface any restorable sessions ("N sessions stopped — `claude-restore` to bring them back").

2. **Add a one-line gist per session — read cheaply, don't deep-analyze.** For each session with a resolvable transcript at `~/.claude/projects/<cwd-with-slashes-as-dashes>/<sessionId>.jsonl`:
   - Skim the *recent* turns only — e.g. `jq` the last few `type=="user"` messages, or read the tail. You're after "what is this session about," not a full summary.
   - **One line each.** The user wants a memory jog, not analysis.
   - If a session has no transcript yet (fresh, never used), say "not started yet" rather than guessing.

3. **Present a compact combined view:** each session as `name · state · last-active · cwd[branch] · «gist»`, then the worktrees — flagging any with **uncommitted work** or **no live session** (those are the ones worth attention). Call out `failed` (a crash that exhausted restarts) and `unmanaged` (a hand-run claude not under systemd) entries.

## Rules

- **Read-only.** Never close, kill, stop, or prune anything. (That's `/prune`.)
- A session is recovered with **`claude-restore <name>`** (or attached live with `dtach -a $XDG_RUNTIME_DIR/claude-<name>.sock`), not by re-running a raw `claude --resume` — the systemd unit owns the conversation id.
- This is the same output as step 2 of the session-start ritual (see AGENTS.md), so reuse it there.
