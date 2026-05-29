---
name: status
description: Quick snapshot of what's live on the box — Claude sessions, Zellij tabs, and git worktrees. Trigger on "/status", "/box-status", "what's running", "status check", "lay of the land". Lighter than `/sessions` (no per-session transcript gist) — use when the user wants the inventory at a glance, not a memory jog.
---

# /status — sessions + tabs + worktrees at a glance

Three sections, no per-session analysis. This is the fast snapshot — when the user wants the read-out of what's alive on the box, not a "what was I doing in each."

For deeper context (one-line gist per session, derived from the transcript), the user wants `/sessions`. For cleanup of stale state, `/prune`. This skill is intentionally narrower than both.

## Steps

1. **Claude sessions** — run `claude-sessions`. Its output already includes the session list and the worktree list with branch / live-session / uncommitted flags. Capture both halves.

2. **Zellij tabs** — for each Zellij session, list its tab names:
   ```
   zellij ls | awk 'NF{print $1}' | sed 's/\x1b\[[0-9;]*m//g'
   ```
   then for each session:
   ```
   zellij --session <name> action query-tab-names
   ```
   Group tabs under their session header.

3. **Render** the three sections in this order — sessions, Zellij tabs, worktrees — each compact:
   - Sessions: `name · status · last-active · cwd[branch]` (skip the resume id here; that belongs in `/sessions`).
   - Zellij: session header, then tab names indented.
   - Worktrees: path, branch, `live-session` count, uncommitted flag.

4. **Flag drift if it's obvious** — but only the kind that pops out from this read-out itself: a session named `live · ?` (broken bridge pointer), a Zellij tab with no matching claude process, a worktree with no live session AND no merged PR. Don't go hunting; just point at what's visible.

## Rules

- **Read-only.** Never kill, park, prune, or close anything.
- Don't read transcripts — that's `/sessions`'s job and adds latency this skill is meant to avoid.
- Keep the whole output skimmable on one screen. Tables and short lines, not paragraphs.
