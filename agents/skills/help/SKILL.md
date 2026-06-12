---
name: help
description: List all available skills and what each does. Trigger on "/help", "what skills do I have", "what can you do here", "list commands/skills".
---

# /help — list available skills

Give the user a clean, scannable list of every skill they can invoke: `name` — one-line description. One line each, no deep explanation.

## Steps

1. Source the list from the skills surfaced to you this session (the available-skills system list) and/or by reading the `name` + `description` frontmatter of each `~/.agents/skills/*/SKILL.md`.
2. Group by provenance, in this order:
   - **Custom** — home-grown workflow skills (symlink target under `~/code/devbox/agents/skills/`).
   - **Vendored** — third-party, easyskills-managed (symlink target under `…/easyskills/.skills/`). `readlink` distinguishes the two; or just `easyskills --global list`. Mark patched ones (entries in `~/code/devbox/easyskills/skills.patches/`) with a note.
   - **Built-in / plugin** skills briefly after, if any are present.
3. Present as a tight list. End by reminding the user they invoke any with `/<name>`.

## Example shape

```
Available skills — invoke with /<name>:

  /sessions          — full inventory: sessions (with gists), worktrees, dev stacks
  /prune             — clean-up review board: everything + suggested actions, you decide
  /park              — stop a session, keep the conversation (reversible)
  /kill              — destroy a session + its worktree, deliberately
  /new-chat-session  — open a fresh general-purpose session
  /new-work-session  — open a session that clarifies a task, then works in its own worktree
  /new-repo          — create a brand-new GitHub repo + dev contract + session
  /clone-repo        — clone + set up an existing GitHub repo on the devbox
  /serve             — start/stop/restart the dev servers for the current worktree
  /help              — this list

Vendored (third-party, easyskills-managed — see docs/skills.md):

  /grill-me          — relentless interrogation of your plan
  /tdd               — enforced red-green-refactor
  /agent-browser     — ad-hoc browser automation (snapshot → refs)
  /find-skills ◆     — discover skills on skills.sh (patched: installs need your OK)
  …
```

Keep it current — read the actual skills present, don't hardcode a stale list.
