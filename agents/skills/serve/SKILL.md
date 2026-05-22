---
name: serve
description: Start, stop, restart, or check the dev servers for the current repo/worktree. Trigger on "/serve", "serve", "run the app", "start dev", "spin up the api", "stop the servers", "kill it", "restart the server", "is anything on :3030?", "what's running?". Handles cross-worktree port conflicts — inspects what's bound, finds which worktree owns each process, and asks before killing competing servers.
---

# /serve — per-worktree dev server runner

Every repo under `~/code/` carries its dev contract in `.mise.toml`. "Run the app" means: figure out *this repo's* dev tasks, check what's already alive across the whole box, and resolve conflicts with the user before acting. Same idea in reverse for "stop the app."

This skill is project-agnostic — it does not hardcode ports, task names, or service shapes. Inspect, then decide.

## Look first, don't assume

Before *any* action, gather:

- **Current worktree.** `pwd` + `git rev-parse --show-toplevel`. Note the repo root and whether it's a worktree (sibling like `<repo>-<task>`) or the main checkout.
- **What "running the app" means here.** `mise tasks` (or read `.mise.toml`). Dev shapes vary — could be one umbrella `dev`, or per-service `api:dev` + `mobile:dev`, or something else. Don't guess.
- **What's already bound.** `ss -tlnp` for listening ports. For each pid of interest, `readlink /proc/<pid>/cwd` tells you which directory (and therefore which worktree) the process came from. Walk parents (`ps -o ppid= -p <pid>`) when the binding process is a worker, not the supervisor.
- **Backing infra.** `docker ps` for postgres / redis / minio / etc. used by the repo.

Only after you have this picture should you propose an action.

## Decision tree (start)

| Situation | Action |
|---|---|
| Nothing relevant is bound | Start the dev tasks from the current worktree's cwd. |
| Same-worktree process already running | No-op. Tell the user it's already up. |
| **Different worktree of the same repo is running** | **Surface the conflict, ask before killing.** Name the other worktree by path. |
| Different repo using a port you need | Surface and ask. Don't assume intent. |
| Backing infra is down but the dev task needs it | Tell the user; offer to run the repo's infra task (`mise run infra:up` or equivalent). Don't auto-start docker. |

For the "ask before killing" cases, phrase concretely:

> "Metro (:8081) and the API (:3030) are running from `~/code/kost-auth-refactor`. Stop them so we can start fresh from `~/code/kost-wishlist-audit`?"

Wait for explicit approval. Never auto-kill cross-worktree.

## Decision tree (stop)

| Situation | Action |
|---|---|
| User says "stop"/"kill"/"shut down" the app | Find what's tied to the current worktree via `/proc/<pid>/cwd`; TERM → wait → KILL. Confirm ports are free. |
| User wants to stop a *specific* worktree (named) | Same procedure but scoped to that worktree's cwd. |
| Backing infra (docker) | Leave it up unless the user explicitly asks. It's shared across worktrees and usually safe to keep running. |

## Killing cleanly

```
kill -TERM <pid>
# wait ~1s
kill -KILL <pid>   # only if still alive
```

Watch for respawn: some dev runners (nx, watchexec, expo) spawn worker processes that the supervisor re-launches if killed alone. If the port re-binds within seconds after a TERM, walk up to the supervisor — `ps -o ppid= -p <pid>` — and kill that. The right thing to kill is usually the *first non-shell ancestor* in the tree.

After every kill round, re-check `ss -tlnp` to confirm the port is free before starting anything new on it.

## Starting somewhere persistent

Long-running dev tasks must outlive the chat session, so they need a real home:

- **Preferred:** a fresh zellij tab in the current session (if `$ZELLIJ` is set). Use `zellij action new-tab --name <task> --cwd <wt-path> --layout <inline-kdl-tempfile>` so the tab runs `bash -ic "mise run <task>"`. User can swipe to the tab for logs.
- **Fallback:** background the task with `nohup mise run <task> > /tmp/<repo>-<task>.log 2>&1 &` from inside the worktree's cwd. Tell the user where the log file is.

After starting, **wait for the port to actually bind** before reporting success — poll `ss -tln | grep -q ':<port>'` with a 30s timeout. A task that exits silently (missing env var, bad migration, port already in use someone forgot about) should fail loudly, not be reported as "running."

## Reporting back

After any action, give the user a precise status:

- What's now running, from which worktree, on which ports.
- What you stopped (and from where).
- What you left alone (and why, if non-obvious — e.g., "left postgres container up, shared across worktrees").

If the user is testing on phone, mention that the URL/port didn't change so the Expo Go session will reconnect on the next request.

## Inspection-only requests

If the user is *asking* rather than acting ("what's running on :3030?", "is metro up?"), do only the **look** phase. Don't kill, don't start. Just report what `ss -tlnp` + `readlink /proc/<pid>/cwd` + `docker ps` show, in a sentence or two.
