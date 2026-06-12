---
name: park
description: Park the current Claude session (or a named one) — stop the process, keep the conversation and the worktree. Trigger on "/park", "park this session", "park yourself", "park <name>". Surfaces in-flight work (uncommitted changes, unpushed commits, open PRs) and re-asks before stopping. Fully reversible with `claude-restore <name>`.
---

# /park — stop a session, keep everything

Parking stops the session's systemd unit but keeps the env file, the pinned
conversation id, and the worktree — `claude-restore <name>` brings the exact
conversation back. Nothing is lost; this is "put it down", not "throw it away".
For the destructive version (forget the session + remove its worktree), that's
`/kill`.

## Steps

1. **Resolve the target.** If the user named a session, that's the target.
   Otherwise the target is *this* session — find its name by matching the
   conversation id against the session env files:
   ```bash
   grep -l "SESSION_ID=$CLAUDE_CODE_SESSION_ID" ~/.config/claude-sessions/*.env
   ```
   The name is the matching filename minus `.env`. No match → this session is
   unmanaged (not systemd-spawned); say so and stop — there is no unit to park.

2. **WIP sweep.** Read `CWD=` from the env file and check that checkout for
   in-flight work:
   - uncommitted changes — `git status --porcelain` (count staged/unstaged/untracked)
   - unpushed commits — `git log @{u}..HEAD --oneline` (or "no upstream" if the
     branch was never pushed)
   - an open PR — `gh pr list --head <branch> --state open`
   - a non-default branch checked out in a *main* checkout (a smell worth naming)

   Parking destroys none of this — the worktree stays — but the user asked to be
   told, so tell them.

3. **Confirm.** If anything surfaced in step 2, present it (one line per finding)
   and ask again whether to park anyway. If the sweep is clean, a single
   confirmation is enough — and skip even that when the user's instruction was
   already explicit and unambiguous ("park yourself now").

4. **Park.** Run `claude-park <name>`.
   **Self-park ordering:** the command stops this very process — there is no
   turn after it. Put the farewell (what was parked, any WIP left behind, and
   that `claude-restore <name>` reverses it) in the *same message*, before the
   tool call.

## Rules

- Parking another session mid-task is safe process-wise (the conversation
  resumes), but the agent in it may be mid-tool-loop — prefer parking sessions
  that are idle, and say so if the transcript shows recent activity.
- Never park by raw `systemctl --user stop` — `claude-park` records the park to
  `~/.claude/parked-sessions.log` first, which is the whole point.
