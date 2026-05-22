---
name: help
description: List all available skills and what each does. Trigger on "/help", "what skills do I have", "what can you do here", "list commands/skills".
---

# /help — list available skills

Give the user a clean, scannable list of every skill they can invoke: `name` — one-line description. One line each, no deep explanation.

## Steps

1. Source the list from the skills surfaced to you this session (the available-skills system list) and/or by reading the `name` + `description` frontmatter of each `~/.agents/skills/*/SKILL.md`.
2. Lead with the devbox-custom skills (the ones in `~/code/devbox/agents/skills/`), since those are the home-grown workflow. Mention built-in / plugin skills briefly after, if any are present.
3. Present as a tight list. End by reminding the user they invoke any with `/<name>`.

## Example shape

```
Available skills — invoke with /<name>:

  /sessions          — list active sessions + worktrees, with a gist of each
  /prune             — find stale worktrees/sessions and clean them up (with your OK)
  /new-chat-session  — open a fresh general-purpose session
  /new-work-session  — open a session that clarifies a task, then works in its own worktree
  /clone-repo        — clone + set up a new GitHub repo on the devbox
  /parallel-work     — (auto) guidance for branching work into a worktree
  /run-app           — start/stop/restart the dev servers for the current worktree
  /help              — this list
```

Keep it current — read the actual skills present, don't hardcode a stale list.
