---
name: serve
description: Start, stop, restart, or check the dev servers for the current repo/worktree. Trigger on "/serve", "serve", "run the app", "start dev", "spin up the api", "stop the servers", "kill it", "restart the server", "is anything on :3030?", "what's running?". Handles cross-worktree port conflicts — inspects what's bound, finds which worktree owns each process, and asks before killing competing servers.
---

# /serve — per-worktree dev server runner

Every repo under `~/code/` carries its dev contract in `.mise.toml`. "Run the app" means: figure out *this repo's* dev tasks, check what's already alive across the whole box, resolve conflicts with the user, then start the stack **under process-compose** so it outlives the chat and the Zellij viewer. Same idea in reverse for "stop the app."

Dev servers are **on-demand and restart-fresh** — bring them up while developing, tear them down when done. They are deliberately *not* hosted in Zellij (the dashboard is disposable — see `docs/sessions.md`) and *not* supervised by systemd (that's for agent sessions). process-compose is their home.

This skill is project-agnostic — it does not hardcode ports, task names, or service shapes. Inspect, then decide.

## The process-compose convention

One dev stack per repo/worktree, addressed by a per-project unix socket so `zj`'s dashboard and this skill agree on where it lives:

```
PC_SOCK="$XDG_RUNTIME_DIR/pc-<name>.sock"     # <name> = basename of the repo/worktree root
```

- **Start (detached):** `process-compose -f <config> -U -u "$PC_SOCK" -D up`
- **Attach the TUI:** `process-compose attach -U -u "$PC_SOCK"`  (this is what the dashboard's "services" tab runs)
- **Status (headless):** `process-compose process list -U -u "$PC_SOCK"`
- **Stop everything:** `process-compose down -U -u "$PC_SOCK"`

`<config>` is the repo's committed **`process-compose.yaml`** if it has one (preferred). If it doesn't yet (mid-migration), synthesize a temp one from the repo's `mise` dev tasks — see "Starting" below — and mention that committing a `process-compose.yaml` would make this first-class.

## Look first, don't assume

Before *any* action, gather:

- **Current worktree.** `pwd` + `git rev-parse --show-toplevel`. Note the repo root and whether it's a worktree (sibling like `<repo>-<task>`) or the main checkout. `<name>` for the socket is `basename` of this root.
- **Is a stack already up for it?** `[ -S "$PC_SOCK" ]` and `process-compose process list -U -u "$PC_SOCK"`.
- **What "running the app" means here.** `mise tasks` (or read `.mise.toml`). Dev shapes vary — one umbrella `dev`, or per-service `api:dev` + `mobile:dev`, or something else. Don't guess.
- **What's already bound.** `ss -tlnp` for listening ports. For each pid of interest, `readlink /proc/<pid>/cwd` tells you which worktree the process came from. Walk parents (`ps -o ppid= -p <pid>`) when the binding process is a worker, not the supervisor.
- **Backing infra.** `docker ps` for postgres / redis / minio / etc.

Only after you have this picture should you propose an action.

## Decision tree (start)

| Situation | Action |
|---|---|
| Nothing relevant is bound, no stack socket | Start the stack under process-compose from the current worktree. |
| Stack already up for *this* worktree | No-op. Tell the user it's up; offer `process-compose attach` / `zj <name>`. |
| **Different worktree of the same repo is running** | **Surface the conflict, ask before stopping it** (`process-compose down` on its socket). Name the other worktree by path. |
| Different repo using a port you need | Surface and ask. Don't assume intent. |
| Backing infra down but the stack needs it | The stack should declare infra as a process with health/readiness so process-compose orders it. If infra is a separate `mise run infra:up` (docker), offer to run it; don't auto-start docker. |

For "ask before killing" cases, phrase concretely:

> "Metro (:8081) and the API (:3030) are running from `~/code/kost-auth-refactor`. Stop that stack so we can start fresh from `~/code/kost-wishlist-audit`?"

Wait for explicit approval. Never auto-stop a cross-worktree stack.

## Starting under process-compose

From the worktree root, with `PC_SOCK` set as above:

- **Committed config:** `process-compose -f process-compose.yaml -U -u "$PC_SOCK" -D up`
- **No committed config yet (transition):** write a minimal temp config from the repo's dev tasks and start it, e.g.

  ```yaml
  # /tmp/pc-<name>.yaml — synthesized from .mise.toml; commit a real process-compose.yaml to make this first-class
  processes:
    api:    { command: "mise run api:dev" }
    mobile: { command: "mise run mobile:dev" }
  ```
  then `process-compose -f /tmp/pc-<name>.yaml -U -u "$PC_SOCK" -D up`.

`-D` (detached) means the stack keeps running after you return; the user attaches its TUI via `zj <name>` (the "services" tab) or `process-compose attach -U -u "$PC_SOCK"`.

After starting, **wait for the port(s) to actually bind** before reporting success — poll `ss -tln | grep -q ':<port>'` with a ~30s timeout. A stack that exits silently (missing env var, bad migration, port already taken) should fail loudly; check `process-compose process list -U -u "$PC_SOCK"` and surface the failed process's logs.

## Stopping

| Situation | Action |
|---|---|
| "stop"/"kill"/"shut down" the app | `process-compose down -U -u "$PC_SOCK"` for the current worktree. Confirm ports are free with `ss -tlnp`. |
| Stop a *specific* worktree (named) | Same, with that worktree's `PC_SOCK`. |
| A stray pre-migration server (nohup / old zellij tab, not under process-compose) | Fall back to pid hunting: find it via `/proc/<pid>/cwd`, TERM → wait → KILL, walk to the supervisor if it respawns. |
| Backing infra (docker) | Leave it up unless asked. Shared across worktrees, usually safe to keep. |

After stopping, re-check `ss -tlnp` to confirm the ports are free.

## Inspection-only requests

If the user is *asking* rather than acting ("what's running on :3030?", "is metro up?"), do only the **look** phase: report `process-compose process list` for any live stack socket, plus `ss -tlnp` + `readlink /proc/<pid>/cwd` + `docker ps`. Don't start or stop anything.

## Reporting back

After any action, give a precise status: what's now running (from which worktree, on which ports, under which `PC_SOCK`), what you stopped, and what you left alone (e.g. "left the postgres container up — shared across worktrees"). If the user is testing on phone, mention the URL/port didn't change so Expo Go reconnects on the next request.
