---
name: kill
description: Permanently kill the current Claude session (or a named one) and remove its worktree. Trigger on "/kill", "kill this session", "kill yourself", "kill <name> and its worktree". Surfaces uncommitted changes, unpushed commits, and unmerged PRs, and re-asks for explicit confirmation before destroying anything. Never removes a repo's main checkout.
---

# /kill — destroy a session and its worktree, deliberately

The destructive sibling of `/park`: stops the unit, *forgets* the session
(removes its env file, so it leaves `claude-restore`), and removes its linked
worktree + local branch. The transcript in `~/.claude/projects/` survives, and
`~/.claude/killed-sessions.log` records the conversation id, so a deliberate
`claude-spawn --resume <id>` can still resurrect the conversation — but the
worktree and any uncommitted work in it are gone for real.

If the user only wants the session out of the way for now, that's `/park`.

## Steps

1. **Resolve the target.** Named session → that one. Otherwise this session:
   ```bash
   grep -l "SESSION_ID=$CLAUDE_CODE_SESSION_ID" ~/.config/claude-sessions/*.env
   ```
   Name = matching filename minus `.env`. No match → unmanaged session: nothing
   to kill via systemd; say so and stop.

2. **Classify the cwd.** Read `CWD=` from the env file and determine what it is:
   ```bash
   git -C "$cwd" rev-parse --git-dir --git-common-dir
   ```
   - Paths differ → **linked worktree**; removal is on the table.
   - Paths equal (or not a repo) → **main checkout**; it is NEVER removed —
     killing here only stops + forgets the session. Tell the user that's the
     scope before they confirm.

3. **WIP sweep — stricter than /park, because this destroys.** In the cwd check:
   - uncommitted changes (`git status --porcelain`) — these are **lost** on kill
   - stashes (`git stash list`) — also lost with the worktree
   - unpushed commits (`git log @{u}..HEAD --oneline`, or "branch never pushed" —
     commits only reachable here are **lost**)
   - PR state (`gh pr list --head <branch> --state all --json state,number`) —
     OPEN (work in flight), NONE (never PR'd), CLOSED (abandoned?), MERGED (safe)
   - gitignored env files (`git ls-files --others --ignored --exclude-standard |
     grep -E '(^|/)\.env'`) — worth one line; they don't follow worktrees

4. **Confirm — always, and twice when it bites.** Killing is destructive, so
   always confirm once, spelling out exactly what goes (session forgotten,
   worktree path removed, branch deleted) and what stays (transcript, remote
   branch, merged PR). If step 3 surfaced anything (uncommitted work, unpushed
   commits, a non-MERGED PR), present each finding and require a second,
   explicit confirmation that acknowledges the loss — "yes, discard the 3
   uncommitted files" — not just "yes".

5. **Kill.** Run:
   ```bash
   claude-kill <name> --rm-worktree           # clean worktree
   claude-kill <name> --rm-worktree --force   # only when the user confirmed discarding uncommitted work
   ```
   Omit `--rm-worktree` if the user wants the checkout kept.
   **Self-kill ordering:** there is no turn after this — put the farewell (what
   was destroyed, where the kill log is, how to resurrect the conversation) in
   the *same message*, before the tool call. `claude-kill` detects self-kill and
   hands cleanup to a transient systemd unit, so the worktree removal completes
   after this process dies.

## Rules

- **Never remove a main checkout.** `claude-kill` guards this too, but don't
  even propose it.
- **`--force` only after the user explicitly acknowledged the specific loss.**
  Quote the findings back; don't bury them in a generic "are you sure?".
- Don't bypass `claude-kill` with raw `systemctl stop` + `rm` + `git worktree
  remove` — the script orders the kill log, unit stop, forget, and removal
  correctly, including the self-kill case.
