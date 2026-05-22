---
name: new-work-session
description: Open a new Claude session dedicated to making code changes — it clarifies the task with you first, then creates a git worktree before writing any code. Trigger on "/new-work-session", "new work session", "start a session to build X", "open a session to work on Y". Use this (not /new-chat-session) whenever the new session will edit code.
---

# /new-work-session — spawn a session that works in its own worktree

Open a fresh session primed to do code work the safe way: **clarify → worktree → code**. The priming lives in `work-protocol.md` (this skill's directory) and is injected via `--append-system-prompt`, so the new session follows the protocol from its first turn — it won't touch code until it has clarified the task and created a worktree.

## Steps

1. Decide the **cwd** — the repo the worktree will branch from, usually the main checkout (e.g. `~/code/kost`) — and a short, provisional **name** for the session. (The real worktree slug is chosen *inside* the new session after clarifying, so the name here can just be the repo or a rough topic.) Run `claude-sessions` first to avoid a name collision.
2. Spawn it with the protocol:
   ```bash
   claude-spawn --name <name> --cwd <cwd> \
     --prompt-file ~/code/devbox/agents/skills/new-work-session/work-protocol.md
   ```
3. Tell the user it's up. When they attach and describe what they want, the new session will clarify back-and-forth, then `wt new <slug>`, then work entirely inside that worktree.

The point: the new session's *first code change* lands on its own branch — never on the main checkout.
