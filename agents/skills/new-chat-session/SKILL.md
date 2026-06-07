---
name: new-chat-session
description: Open a new general-purpose Claude session in a fresh Zellij tab, attachable from the phone. Trigger on "/new-chat-session", "open a new session", "new chat session", "spawn a session", "give me another agent". For a session that will make code changes, use /new-work-session instead.
---

# /new-chat-session — spawn a general-purpose session

Open a fresh Claude session the user can drive from the phone. No worktree, no task priming — just a clean agent.

## Steps

1. Decide the **cwd** and a short, unique **name** (the name is both the remote-control name and the tab name). Run `claude-sessions` first to avoid a name that collides with an existing tab/session.

   **cwd rules:**
   - Brainstorm tied to an existing repo's feature/integration → that repo's cwd (e.g. a kost feature → `~/code/kost`).
   - **Pre-repo brainstorm** (no commitment yet on whether code gets written or where it lives) → `~/code/` itself. Don't park it in a sibling repo just for company — the cwd implies project context that isn't there, and a later "let's make this real" needs a respawn. `~/code/` is the honest default for "we haven't decided yet."
   - When ambiguous, ask.
2. Spawn it:
   ```bash
   claude-spawn --name <name> --cwd <cwd>
   ```
3. Tell the user it's up and to refresh the phone Claude app — it appears in the session list within ~10s.

For code work that should live on its own branch, use `/new-work-session` instead — it primes the session to create a worktree before editing anything.
