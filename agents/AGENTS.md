# Agent instructions for the devbox

You are running on a personal Hetzner Cloud VPS (Debian 12) used as a remote dev environment for multiple projects. The owner drives sessions from a phone via Claude's Remote Control feature or by SSHing in from a laptop. This file is loaded into every session for both Claude Code and Codex CLI (`~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` both symlink here).

The VPS itself is provisioned declaratively from `~/code/devbox` (Ansible + chezmoi). When something looks misconfigured, look there first.

## Layout

- **Repos**: `~/code/<project-name>/` (e.g. `~/code/kost`). Each is its own git repo.
- **VPS infra source**: `~/code/devbox`.
- **Cross-agent home**: `~/.agents/` — `AGENTS.md` (this file) and `skills/` (loaded on demand).
- **Workspaces**: Zellij sessions, one per project. Launch with `zj <project>`.

## Tools

| Tool | What for |
|---|---|
| **mise** | Per-project Node/Bun/pnpm versions + tasks + env (`.mise.toml`). Always prefer `mise run <task>` over guessing commands. |
| **Zellij** | Workspace persistence. Per-project `zellij.kdl` layout. |
| **Claude Code** + **Codex CLI** | Both available, both honor this AGENTS.md and the shared `~/.agents/skills/`. |
| **Claude Squad** (`cs`) | TUI for parallel agents on git worktrees. |
| **Tailscale** | Private mesh. Use tailnet IPs (`100.x.y.z`), never the public IP. |
| **`wt`** | Worktree + PR + merge wrapper (see below). Use this instead of raw `git worktree` / `gh pr` commands. |
| **`gh`** | GitHub CLI. Use for issues, PRs, CI status, releases. |
| **ripgrep** (`rg`), **fd**, **jq** | Search and JSON parsing. Prefer over `grep -r` / `find` / `python -m json.tool`. |
| **process-compose** | Headless service orchestration (Postgres, Redis, workers). Not for TUIs. |
| **ntfy** | Push notifications to phone (installed dormant — `curl -d "msg" ntfy.sh/$NTFY_TOPIC` once a topic is wired). |
| **chezmoi** | Dotfile manager. Source lives in `~/code/devbox/chezmoi/`. |

## Branch / PR / merge workflow

Use the `wt` wrapper, not raw git/gh, for the worktree → PR → merge lifecycle:

| Command | Effect |
|---|---|
| `wt new <task>` | Branch a worktree from **`origin/<default>`** (fetches first). Creates `../<repo>-<task>` with branch `<task>`. |
| `wt pr [gh-args…]` | Fetch + rebase on `origin/<default>` + `git push --force-with-lease` + `gh pr create`. Pauses on conflicts. |
| `wt merge [strategy]` | Merge the current worktree's PR (default `--squash`, `--delete-branch`) + remove worktree + delete local branch + pull `<default>` forward. |
| `wt rm <task> [--force]` | Remove a worktree. Refuses unless the PR is MERGED (or `--force`). |
| `wt list` | List worktrees in the current repo. |
| `wt prune` | Sweep merged-PR worktrees across all repos. Cron runs this every 30 min. |
| `wt help` | Full reference. |

**Always** use `wt new` instead of `git worktree add`. **Always** use `wt pr` / `wt merge` instead of `gh pr create` / `gh pr merge`. They handle sync, rebase, and cleanup that's easy to forget manually.

## Repository sync

The VPS does **not** auto-pull repos on a schedule. Freshness is enforced at the moments where it matters:

- `wt new` fetches origin and branches from `origin/<default>` — the new worktree always starts from current state, no manual pull needed.
- `wt pr` fetches and rebases — feature branch is current with `origin/<default>` before the PR opens. Conflicts surface to you as a normal rebase pause; resolve, `git rebase --continue`, re-run `wt pr`.
- `wt merge` pulls the default branch forward after merge, leaving the main checkout current.
- A 30-min `wt prune` cron sweeps worktrees whose PRs were merged outside `wt merge` (e.g., from the GitHub mobile UI). No action needed.

If you find yourself wanting to `git pull` on a default branch manually, you don't need to — the next `wt new` or `wt merge` handles it.

## Conventions

- **Don't `sudo`** unless necessary. `fum4` has NOPASSWD sudo but day-to-day work doesn't need it.
- **Don't expose anything to the public internet.** All inbound traffic except SSH is firewalled; reach dev servers over Tailscale.
- **Per-repo dev contract**: each repo's `.mise.toml` (tasks) and `zellij.kdl` (workspace) are the source of truth for "how to run this project." Add them when scaffolding a new repo.
- **The VPS is ephemeral.** Anything not in git or in `~/code/devbox/` is at risk on rebuild. Don't store load-bearing state outside these.
- **Devbox is the backbone — keep `~/code/devbox` in sync.** This `AGENTS.md`, the `skills/` tree, ansible roles, chezmoi sources, and `wt`/scripts in `~/.local/bin` all live there. When a change belongs in devbox (a rule update, a new skill, an ansible role tweak, a dotfile edit), edit it under `~/code/devbox/<path>`, commit, push, then apply it locally with `chezmoi apply` or by re-running the relevant ansible role. The live copies (`~/.agents/AGENTS.md`, `~/.bashrc`, `~/.local/bin/wt`, …) get clobbered on the next provision — don't patch them directly.
- **Long-running processes** go in Zellij tabs, not bare SSH sessions. Otherwise they die when SSH drops.
- **Globals via mise, not npm/pnpm**: don't install global npm/pnpm packages. Add them as `[tools]` in a repo's `.mise.toml`.
- **Don't edit chezmoi-managed files directly**: `~/.bashrc`, `~/.config/zellij/config.kdl`, `~/.local/bin/*`. Edit `~/code/devbox/chezmoi/` and `chezmoi apply` (or run the ansible role).
- **New tools go through Ansible**: don't `apt install X` ad-hoc. Add a role in `~/code/devbox/ansible/roles/` so the VPS stays reproducible.

## Common operations

| Goal | How |
|---|---|
| List active workspaces | `zellij ls` |
| Open / attach a project | `zj <project>` |
| Detach from a workspace | `Ctrl+O` then `d` |
| Run a task | `mise run <task>` (after `cd <repo>`) |
| List tasks for current repo | `mise tasks` |
| Start new unrelated work | `wt new <task>` (creates worktree branched from `origin/<default>`) |
| Open a PR | `wt pr` (rebase + push + `gh pr create`) |
| Merge + clean up | `wt merge` |

For when to use a worktree (and when not), the `parallel-work` skill in `~/.agents/skills/parallel-work/SKILL.md` has the full decision tree.
