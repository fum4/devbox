---
name: status
description: Quick snapshot of what's live on the box — Claude agent sessions, dev-server stacks, and git worktrees. Trigger on "/status", "/box-status", "what's running", "status check", "lay of the land". Lighter than `/sessions` (no per-session transcript gist) — use when the user wants the inventory at a glance, not a memory jog.
---

# /status — sessions + dev servers + worktrees at a glance

Three sections, no per-session analysis. This is the fast snapshot — when the user wants the read-out of what's alive on the box, not a "what was I doing in each."

For deeper context (one-line gist per session, derived from the transcript), the user wants `/sessions`. For cleanup of stale state, `/prune`. This skill is intentionally narrower than both.

## Steps

1. **Agent sessions** — run `claude-sessions`. Its output already includes the systemd-managed session list (active / stopped / failed, cwd[branch], conversation id), any *unmanaged* stray claude processes, and the worktree list with branch / live-session / uncommitted flags. Capture all of it.

2. **Dev-server stacks** — list any running process-compose stacks (these are the dev servers, under `/serve`):
   ```
   ls "$XDG_RUNTIME_DIR"/pc-*.sock 2>/dev/null
   ```
   For each socket, the project is the `pc-<name>.sock` stem; if you want the process list, `process-compose process list -U -u <sock>`. Also glance at `ss -tlnp` for bound dev ports.

3. **Render** the three sections in this order — agent sessions, dev-server stacks, worktrees — each compact:
   - Sessions: `name · state · last-active · cwd[branch]` (skip the conversation id here; that belongs in `/sessions`). Note any `failed` (a real crash) or `unmanaged` entries.
   - Dev stacks: `<name>` + ports bound (or "none up").
   - Worktrees: path, branch, live-session, uncommitted flag.

4. **Flag drift if it's obvious** — only what pops out from this read-out itself: a `failed` agent unit (crashed, exhausted restarts), an `unmanaged` claude process (pre-migration / hand-run — could be re-spawned via `claude-spawn`), a worktree with no live session AND no merged PR. Don't go hunting; just point at what's visible.

Zellij dashboards (`zj <project>`) are disposable views, not where work lives — they're not part of this inventory. If the user explicitly asks which dashboards are open, `zellij ls`.

## Rules

- **Read-only.** Never kill, park, prune, stop, or close anything.
- Don't read transcripts — that's `/sessions`'s job and adds latency this skill is meant to avoid.
- Keep the whole output skimmable on one screen. Tables and short lines, not paragraphs.
