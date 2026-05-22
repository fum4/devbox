---
name: new-chat-session
description: Open a new general-purpose Claude session in a fresh Zellij tab, attachable from the phone. Trigger on "/new-chat-session", "open a new session", "new chat session", "spawn a session", "give me another agent". For a session that will make code changes, use /new-work-session instead.
---

# /new-chat-session — spawn a general-purpose session

Open a fresh Claude session the user can drive from the phone. No worktree, no task priming — just a clean agent.

## Steps

1. Decide the **cwd** (which repo) and a short, unique **name** (it's both the remote-control name and the tab name). Default the cwd to the current repo if it's obvious; only ask if ambiguous. Run `claude-sessions` first to avoid a name that collides with an existing tab/session.
2. Spawn it:
   ```bash
   claude-spawn --name <name> --cwd <cwd>
   ```
3. Tell the user it's up and to refresh the phone Claude app — it appears in the session list within ~10s.

For code work that should live on its own branch, use `/new-work-session` instead — it primes the session to create a worktree before editing anything.
