---
name: parallel-work
description: When starting a task or feature unrelated to current work in the same repo, create a git worktree via `wt new` so parallel agents can work without conflict. Trigger when the user asks to start a new feature, fix a separate bug, work on a parallel concern, or run multiple agents on the same repo.
---

# Parallel work via git worktrees

When the user starts a task that is **unrelated to current work in this repo**, use a git worktree via the `wt` wrapper instead of switching branches in place.

## Why

- Multiple parallel agents (typically via Claude Squad / `cs`) each work in their own worktree without committing or stashing each other's changes.
- The main checkout keeps its long-running processes (Metro, API, current `claude` session) without restart.
- Context switching is `cd` between sibling directories — no stash, no checkout, no "what file was I on?"
- `wt new` branches from `origin/<default>`, not local default. New work always starts current with the canonical state.

## Lifecycle — use `wt`, not raw git/gh

```bash
wt new <task>          # branch a worktree from origin/<default>
                       # creates ../<repo>-<task> with branch <task>

# … work, commit …

wt pr                  # fetch + rebase on origin/<default> + push + gh pr create
                       # pauses on rebase conflicts — resolve, continue, re-run

# … review, address feedback, push more commits …

wt merge               # merge PR (default --squash, --delete-branch)
                       # then: remove worktree + delete local branch + pull main
```

**Don't** run `git worktree add`, `gh pr create`, or `gh pr merge` directly. The wrappers handle the sync and cleanup that's easy to forget manually.

## Naming conventions

- `<task>` — short kebab-case slug describing the work (`auth-fix`, `receipt-ocr`, `migrate-clerk`)
- Branch name defaults to the task (`auth-fix`)
- Worktree path: `../<repo>-<task>` (sibling to main, e.g. `~/code/kost-auth-fix/`)

## Conflict resolution during `wt pr`

If `wt pr` pauses with rebase conflicts:

1. Resolve the conflicts in the affected files
2. `git add <resolved-files>`
3. `git rebase --continue`
4. If more conflicts surface, repeat
5. Re-run `wt pr` once the rebase finishes — it will push and open the PR

If you decide the conflicts aren't worth resolving (e.g., the base has moved too far), `git rebase --abort` and ask the user how to proceed.

## Per-worktree dev environment

Each worktree is a full repo checkout. It picks up the same `.mise.toml` and `zellij.kdl`. To open a parallel workspace in Zellij:

```bash
zj kost-auth-fix       # new Zellij session for the worktree (separate from kost)
```

The session is named after the directory, so workspaces don't collide.

## Cleanup edge cases

- **`wt merge` after the PR was merged externally** (e.g. you clicked merge on GitHub mobile UI before the agent got there): `wt merge` detects MERGED state and skips the merge step, but still cleans up the worktree.
- **PR closed without merge** (abandoned work): `wt rm <task> --force` to discard. Don't do this without confirming with the user — there might be work worth recovering.
- **Forgot to clean up a worktree**: run the `/prune` skill — it lists worktrees whose PR is MERGED, checks each for a live session + uncommitted work, and removes only the safe ones (with your confirmation). Cleanup is deliberate, never automatic — a cron used to do it but could orphan a live session, so it was removed.

## When NOT to use a worktree

- **Trivial change in the same area** as ongoing work — just edit on the current branch
- **Hotfix to the current branch** — commit on current, push, continue
- **Refactor that overlaps with current work** — conflicts at merge regardless; a worktree doesn't help
- **One-off scripts or exploration that won't be committed** — `git stash` if you need to switch

## Heuristic

The simplest test: **would running two `claude` sessions on this repo at the same time create merge headaches?** If yes → worktree. If no → just work on the current branch.
