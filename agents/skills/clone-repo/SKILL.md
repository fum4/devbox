---
name: clone-repo
description: Triggers when the user asks to clone, set up, or start working on a new GitHub repo on the devbox (typically from github.com/fum4). Walks the agent through clone → check what config already exists → inspect → propose `devbox-scaffold` for whatever is missing → WAIT for user confirmation → scaffold → wire real commands → open the workspace.
---

# Clone + scaffold a new repo on the devbox

When the user asks to clone, set up, or start working on a new repo, follow this workflow. Most repos come from the user's primary GitHub account: **https://github.com/fum4**.

## 1. Clone the repo

Default URL pattern (the devbox's GitHub SSH key is wired for this):

```bash
cd ~/code
git clone git@github.com:fum4/<repo>.git
cd <repo>
```

If the user explicitly names a different account or org (e.g. a fork, a shared org), use that URL instead. Don't assume.

## 2. Check what config the repo already has

Before inspecting or proposing anything, look at the state of the two devbox-managed files:

```bash
ls -1 .mise.toml zellij.kdl 2>/dev/null
```

This gives you one of four cases. Each branches the rest of the flow:

### Case A — both `.mise.toml` and `zellij.kdl` are present

The repo already has its dev contract. **No scaffolding needed.** Tell the user what's there and skip ahead:

> `<repo>` already has both `.mise.toml` and `zellij.kdl`. Mise tasks defined: `<list from mise tasks>`. Workspace tabs: `<read from zellij.kdl>`. Skipping scaffold.

Go straight to step 6 (bring up the workspace). Don't propose scaffolding.

### Case B — only `.mise.toml` is present (no `zellij.kdl`)

The repo has tasks defined but no workspace layout. Inspect `.mise.toml` to see the task names, then **propose scaffolding only `zellij.kdl`** with tabs that reference those tasks:

> `<repo>` has `.mise.toml` (tasks: `<list>`) but no `zellij.kdl`. I'd scaffold the workspace with:
>
> ```
> devbox-scaffold <tab>:<task> …
> ```
>
> That adds tabs running the existing mise tasks. Confirm or change?

Wait for the user. Then go to step 4.

### Case C — only `zellij.kdl` is present (no `.mise.toml`)

The repo has a workspace layout but no task config. Read `zellij.kdl` to identify tabs and the `mise run <task>` references inside them, then **propose scaffolding only `.mise.toml`** with placeholders for those tasks:

> `<repo>` has `zellij.kdl` (tabs: `<list>` running `<tasks>`) but no `.mise.toml`. I'd scaffold tool versions + task placeholders with:
>
> ```
> devbox-scaffold <tab>:<task> …
> ```
>
> The script skips files that already exist, so it won't touch `zellij.kdl` — only writes `.mise.toml`. Confirm or change?

Wait for the user. Then go to step 4.

### Case D — neither file is present

The repo has no devbox-managed config. Inspect the repo (next step), then propose a full scaffold.

## 3. Inspect the repo (cases B / C / D)

Read these to figure out what dev commands exist:

- `package.json` → `"scripts"` (look for `dev`, `dev:*`, `start`, `serve`, `watch`)
- `Cargo.toml` → `[[bin]]` and `[features]`
- `pyproject.toml` / `Pipfile` → Python entry points
- `Makefile` / `justfile` → ad-hoc task names
- `docker-compose.yml` / `compose.yml` → backing services (suggests an `infra` tab)
- `README.md` — the dev command is almost always documented

Identify:

- **Long-running services** (api, frontend, worker, ws, …)
- **Their dev command** (`pnpm dev:api`, `cargo run --bin server`, `python -m worker`, etc.)
- **Whether the repo has a Docker compose stack** (suggests an `infra:up` task and an `infra` tab)

For Case B (mise exists), align with the existing task names — don't rename.
For Case C (zellij exists), align with the existing tabs and their referenced tasks.
For Case D (neither), pick reasonable names and let the user correct them.

## 4. Propose the `devbox-scaffold` invocation — WAIT for confirmation

**Do not run `devbox-scaffold` yet.** Show the user what you'd run and ask them to confirm or correct first:

> Based on inspecting `<repo>`, I'd scaffold the workspace with:
>
> ```
> devbox-scaffold <tab>:<task> <tab>:<task> <tab>
> ```
>
> That creates Zellij tabs in addition to the always-on `shell` + `claude` tabs:
> - `<tab>` → auto-runs `mise run <task>` (which I'll wire to `<actual command>`)
> - `<tab>` → empty (you'd start it manually with `<command>`)
> - …
>
> Confirm or change tabs / tasks / commands?

Wait for an explicit reply. The user may want to:

- Add or remove tabs
- Rename tabs or task IDs
- Override the auto-detected command
- Skip scaffolding entirely (e.g. a one-off read of someone else's repo)

If the user is silent or ambiguous, ask again — don't proceed on a guess.

## 5. Run `devbox-scaffold` (only after confirmation)

```bash
devbox-scaffold <tab>:<task> …
```

The script is **safe by default**: it skips files that already exist and only writes what's missing. So whether the repo is in case B, C, or D, you run the same command — the script writes only the gap files.

If the user wants to start fresh and overwrite existing config, use `--force`.

For each file it does write, the script emits TODO placeholders for the actual commands.

## 6. Wire in the real commands (only when `.mise.toml` was written)

Edit `.mise.toml`. Replace each `run = "# TODO: …"` with the real command from your inspection in step 3.

### 6a. Fill in `[tasks.setup]` (the install convention)

Every scaffolded `.mise.toml` includes a `[tasks.setup]` block. This task is run **once per fresh provision** by the `repos` Ansible role (and once when `clone-repo` finishes), and it should be the *first-time install command* for the project. Detect the right command by looking at the repo:

| Files present | `setup` command |
|---|---|
| `package.json` + `pnpm-lock.yaml` | `pnpm install` |
| `package.json` + `bun.lockb` | `bun install` |
| `package.json` + `package-lock.json` | `npm ci` |
| `package.json` + `yarn.lock` | `yarn install --frozen-lockfile` |
| `Cargo.toml` | `cargo fetch` |
| `pyproject.toml` + `uv.lock` | `uv sync` |
| `pyproject.toml` + `poetry.lock` | `poetry install` |
| `pyproject.toml` (other) | `pip install -e .` |
| `Gemfile` | `bundle install` |
| `go.mod` | `go mod download` |
| `Cargo.toml` + extra system deps | `cargo fetch && (whatever the README says)` |

If the project chains multiple steps for first-time setup (codegen, schema generation, fixture loading), include them. Example:

```toml
[tasks.setup]
description = "First-time setup after clone"
run = "pnpm install && pnpm run codegen"
```

Skip this if the repo is a non-installable read-only / library reference (no package manager or build step).

### 6b. Fill in the per-tab dev tasks

Replace each `[tasks."<name>"]` placeholder with the project's actual dev command. Example:

```toml
[tasks."api:dev"]
description = "API dev server (hono on bun, watch mode)"
run = "pnpm dev:api"
```

If a task needs env vars or a working directory other than the repo root, configure them per [mise task docs](https://mise.jdx.dev/tasks/).

In case A (both files present) and case C (mise was already there), skip 6a/6b — the tasks are already wired. But it's worth checking that `setup` exists; if not, add one based on the table above.

## 7. Bring up the workspace

```bash
mise install                # install the project's locked tool versions
mise run setup              # the install convention — runs whatever you wired in 6a
zj <repo>                   # launch Zellij with the layout
```

Inside the **claude tab** (`Ctrl+T 2` from anywhere in the session), type `/remote-control` to register a phone-driveable session for this project.

## 8. Commit the scaffolded files (only what we wrote)

If `zellij.kdl` and/or `.mise.toml` were newly written by us, commit them so any future provision of the devbox (or a collaborator) gets the same workspace by default:

```bash
git add zellij.kdl .mise.toml   # only the ones that actually changed
git commit -m "chore: add mise + zellij workspace config"
```

If this is your default branch and the user is OK pushing: `git push`. If this is a feature branch / fork: use `wt pr` (see AGENTS.md → "Branch / PR / merge workflow").

## 9. Offer to add the repo to the devbox repos list

The devbox keeps a list of repos that should auto-clone on any fresh provision: `~/code/devbox/repos.txt`. Each line is `user/repo` (GitHub shorthand) or a full clone URL.

After everything else is done, ask the user:

> Should I add `<repo>` to `~/code/devbox/repos.txt`? It'll then be cloned automatically the next time you provision a fresh devbox. Skip this if the repo is ephemeral — one-off PR contributions, throwaway experiments, forks you'll delete after merging upstream.

**Wait for the user.** Don't add by default — many clones are ephemeral and shouldn't follow you to every new VPS.

If the user confirms:

1. Append the shorthand to `repos.txt`:
   ```bash
   echo 'fum4/<repo>' >> ~/code/devbox/repos.txt
   ```
   (Or the full URL if non-GitHub.)
2. Commit in the devbox repo:
   ```bash
   cd ~/code/devbox
   git add repos.txt
   git commit -m "chore(repos): add <repo>"
   ```
3. Ask the user whether to push the change (per the project-wide no-unauthorized-push convention). If yes, `git push`.

## When NOT to run this skill

Skip the scaffolding for:

- **Read-only clones** ("clone X so I can look at the code") — clone, stop, no scaffold
- **One-PR contributions** to an upstream — clone, `wt new <task>`, edit, `wt pr`. Don't pollute the repo with our devbox-specific config files
- **Libraries / utilities without dev servers** — `mise install` if there's a `.mise.toml`, otherwise no workspace needed
- **Throwaway experiments** in `/tmp` or similar — don't scaffold ephemeral repos

When in doubt, ask the user "is this a long-lived project we should scaffold for, or one-off?"

## Adding tabs/tasks to an existing config

`devbox-scaffold` only generates fresh files — it doesn't merge into existing ones. If the user wants to **add** a tab to an existing `zellij.kdl` or a **task** to an existing `.mise.toml`, edit the file directly (don't run scaffold with `--force` — that wipes the user's customizations).
