---
name: prune
description: Find stale git worktrees and Claude sessions and clean them up — safely. Trigger on "/prune", "clean up worktrees", "what can I prune", "tidy up sessions", "remove old worktrees". Lists candidates with reasons and waits for confirmation; never removes anything live or with uncommitted work, and parks sessions (records the resume id) rather than killing them.
---

# /prune — considered, session-aware cleanup

This replaces the old auto-prune cron, which removed merged worktrees blindly and once orphaned a live session (a chat was then lost). Cleanup here is deliberate: **inventory → propose with reasons → confirm per item → act** — and nothing recoverable-only-by-luck ever gets destroyed.

## Hard safety rules (do not break these)

- **Never act without per-item confirmation.** List candidates; the user picks.
- **Never touch a worktree with uncommitted changes.** Flag it "has unsaved work — keep."
- **Never touch a worktree that has a live session in it.** Flag it; the session is dealt with first (parked or left).
- **Park sessions, don't kill them.** Use `claude-park <name>` — it records the `claude --resume <id>` line *before* closing the tab, so closing is reversible.

## Steps

1. **Inventory:** run `claude-sessions` — every live session (cwd/worktree, uncommitted count, resume id) and every worktree.

2. **Classify each non-main worktree.** Gather PR state (`gh -R <remote> pr list --head <branch> --state all --json state,number` — catches PRs merged via the GitHub UI too), the uncommitted count, and whether a live session sits in it. Then:

   | Situation | Verdict |
   |---|---|
   | PR **MERGED**, clean, no live session | **prune candidate** — safe to `wt rm <task>` |
   | PR **OPEN** | leave — still in flight (offer `wt merge` only if asked) |
   | uncommitted changes | **keep** — unsaved work, never auto-remove |
   | live session in it | **keep** — handle the session first |
   | no PR at all | leave — unmerged work; ask before discarding |

3. **Sessions (conservative).** A session is a *park candidate* only if the user agrees it's done (e.g. its worktree's PR merged and they're finished). **Idle time alone is not a reason to park** — a session left open for days may be intentional. When in doubt, leave it.

4. **Present** the candidates as a short list, each with its one-line reason, and ask which to act on. Spell out what each action does.

5. **Act on confirmed items only:**
   - worktree → `wt rm <task>` (refuses unless the PR is MERGED — a second safety net; `--force` only if the user explicitly says "discard").
   - session → `claude-park <name>` (logs resume id, then closes the tab).

6. **Report** what was pruned/parked and what was deliberately kept (and why).

## Why it's like this

A cron auto-removed merged worktrees but couldn't see a live session sitting in one, so it orphaned the session's cwd; a careless follow-up then closed the mis-identified tab and lost the chat. `/prune` puts a human in the loop and makes "close a session" mean "park it" — so cleanup is never destructive in a way you can't undo.
