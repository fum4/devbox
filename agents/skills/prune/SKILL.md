---
name: prune
description: Clean-up review board — every session and worktree with liveness + WIP facts and a suggested action each (keep / park / kill / remove); the user picks what happens. Trigger on "/prune", "clean up worktrees", "what can I prune", "tidy up sessions", "remove old worktrees". Never acts without per-item confirmation; suggests parking over killing when in doubt.
---

# /prune — the clean-up review board

Show **everything** — every session (active *and* stopped/parked) and every
worktree — with the facts needed to judge each one, plus a *suggested* action.
Then the user decides, per item, what gets kept, parked, killed, or removed.
This is `/sessions` with a cleanup lens: more state, explicit verdicts, and the
user as the judge.

It replaced an auto-prune cron that once orphaned a live session (a chat was
lost). Cleanup is deliberate: **inventory → facts → suggest → user decides →
act** — nothing recoverable-only-by-luck ever gets destroyed.

## Steps

1. **Inventory:** run `claude-sessions` — every known session (active /
   stopped / failed, last-active, cwd[branch], conversation id), unmanaged
   strays, and every worktree.

2. **Facts per item:**
   - For each **worktree** (and each session cwd that is one): `wt wip <path>`
     — branch, uncommitted count, stashes, unpushed commits, PR state, env
     files. One call gives the whole WIP picture.
   - For each **session**: state + last-active (from step 1); if it helps the
     verdict, a one-line gist from the transcript tail (as `/sessions` does).

3. **Build the review board** — one table, every session paired with its
   worktree (and orphan worktrees / checkout-less sessions as their own rows):

   | session | state · last-active | worktree [branch] | WIP | suggestion + why |

   Suggested verdicts (suggestions, never decisions):
   | Situation | Suggest |
   |---|---|
   | active recently, or any uncommitted/unpushed work | **keep** — in flight |
   | PR OPEN | **keep** — in review (offer `wt merge` only if asked) |
   | session looks done (PR merged, idle), conversation may still be wanted | **park** — reversible (`claude-restore`) |
   | parked/idle a long time + PR MERGED + nothing unpushed | **kill** — forget session, remove worktree |
   | worktree clean + PR MERGED + no session in it | **remove worktree** (`wt rm`) |
   | no PR at all on real commits | **keep & flag** — unmerged work; ask what it is |

   Idle time alone is never a park/kill reason — a session left open for days
   may be intentional. When in doubt, suggest keep or park, not kill.

4. **The user decides.** Ask explicitly which items to act on and *how* —
   park vs kill vs remove-worktree are different fates; don't collapse them
   into one "clean it" yes/no. (AskUserQuestion with multi-select works well:
   one question per suggested-action group.) Anything not explicitly picked is
   kept.

5. **Act on confirmed items only:**
   - park session → `claude-park <name>` (reversible — `claude-restore <name>`)
   - kill session (+ its worktree) → `claude-kill <name> [--rm-worktree]`
     (`--force` only after the user explicitly acknowledged discarding the
     specific uncommitted work, quoted back to them)
   - remove a sessionless worktree → `wt rm <task>` (refuses unless PR MERGED;
     `--force` same rule as above)

6. **Report:** what was parked / killed / removed, what was kept and why, and
   the restore/resurrect handles (`claude-restore <name>`, kill-log line).

## Hard safety rules

- **Never act without per-item confirmation** — including on "obvious" ones.
- **Never `--force` anything** without the user explicitly acknowledging the
  specific loss (name the files / commits, not just "are you sure?").
- **Never remove a main checkout** (`wt wip` says which kind it is; so does
  `claude-kill`'s own guard).
- **Park is the default suggestion over kill** when the conversation might
  still have value — parking costs nothing and reverses cleanly.
