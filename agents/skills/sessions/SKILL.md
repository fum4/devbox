---
name: sessions
description: List every active Claude session and git worktree with a one-line gist of what each is about. Trigger on "/sessions", "what sessions are running", "show me my sessions", "what am I working on where", or as step 2 of the session-start ritual. The gist comes from the actual transcript, never the session name.
---

# /sessions — active session + worktree inventory

Show the user, at a glance, every live Claude session and git worktree, each with a one-line "what it's about" so they can remember or pick up context.

**Do not trust the session name.** Names lie — a tab named `wishlist-audit` ended up doing `ui-fixes` work. Derive the gist from the transcript.

## Steps

1. **Get the facts:** run `claude-sessions`. It prints every live session (name, status, last-active, cwd, mapped worktree, `claude --resume <id>`) and every worktree (branch, which session is in it, uncommitted count). It's process-driven, so it catches sessions even when their `~/.claude/sessions/<pid>.json` is missing.

2. **Add a one-line gist per session — read cheaply, don't deep-analyze.** For each session with a resolvable transcript at `~/.claude/projects/<cwd-with-slashes-as-dashes>/<sessionId>.jsonl`:
   - Skim the *recent* turns only — e.g. `jq` the last few `type=="user"` messages, or read the tail. You're after "what is this session about," not a full summary.
   - **One line each.** The user wants a memory jog, not analysis.
   - If a session has no transcript yet (fresh, never used), say "not started yet" rather than guessing.

3. **Present a compact combined view:** each session as `name · status · last-active · cwd[branch] · «gist» · resume-id`, then the worktrees — flagging any with **uncommitted work** or **no live session** (those are the ones worth attention).

## Rules

- **Read-only.** Never close, kill, or prune anything. (That's `/prune`.)
- Always surface each session's **resume id** — it's how a session is recovered if its tab is closed.
- This is the same output as step 2 of the session-start ritual (see AGENTS.md), so reuse it there.
