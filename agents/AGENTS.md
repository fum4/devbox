# Agent instructions for the devbox

You are running on a personal Hetzner Cloud VPS (Debian 12) -- the devbox -- used as a remote dev environment for multiple projects. The owner drives sessions from a phone via Claude's Remote Control feature or by SSHing in from a laptop.

The VPS itself is provisioned declaratively from `~/code/devbox` (Ansible + chezmoi). When something looks misconfigured, look there first.

## Session start ritual

At the very start of every new session — before addressing the user's first request — do two things, in order:

1. **Greet in an original, funny persona.** Pick a *different* voice each time and commit to it for a line or two — a medieval king, a hype rapper, a noir gumshoe, a pirate, a Shakespearean bard, a breathless sportscaster, a 1950s radio announcer, whatever feels fresh. Land the bit, then drop it. Don't reuse a persona you can tell you've used recently; keep it surprising.
2. **Report the lay of the land.** Show the user every active Claude session and git worktree, each with a one-line "what it's about" (use the `/sessions` skill — don't trust session names alone, peek at the actual cwd/worktree/transcript). This way the user always knows what's running before diving in.

Then proceed with the user's actual request. (This ritual is global across all repos, not just devbox.)

## Layout

- **Repos**: `~/code/<project-name>/` (e.g. `~/code/kost`). Each is its own git repo.
- **VPS infra source**: `~/code/devbox`.
- **Cross-agent home**: `~/code/devbox/agents/` — `./AGENTS.md` (this file) and `./skills/` (loaded on demand).
- **Workspaces**: Zellij sessions, one per project. Launch with `zj <project>`.

## Source of truth: the devbox repo

The devbox is *declarative* — its real state lives in `~/code/devbox` (or `~/_work/devbox` on the laptop), not in the live VPS filesystem. Anything you change live on the VPS that isn't reflected in the repo is drift, and dies on the next rebuild.

**When something is broken, misconfigured, or missing, always check the devbox repo first.** The question is never *"how do I fix this on the live VPS?"* — it's *"where in the devbox repo does this fix belong so it survives a rebuild?"* The answer is almost always one of:

| Concern | Lives at |
|---|---|
| System packages, services, system config | `ansible/roles/<role>/` |
| Shell config + dotfiles | `chezmoi/` (mirror the target path under `dot_<path>`) |
| Per-user scripts on the VPS | `chezmoi/dot_local/bin/executable_<name>` |
| Laptop-side utility scripts | `bin/<name>` |
| Age-encrypted secrets | `ansible/secrets/<name>.age` (pattern: [`docs/secrets.md`](../docs/secrets.md)) |
| Agent rules common across Claude + Codex | this file |
| Agent skills (on-demand capabilities) | `agents/skills/<name>/SKILL.md` |

Fix it there, commit, push. To make the change take effect on the running VPS: chezmoi-managed → `chezmoi apply`; ansible-managed → `ansible-playbook ... --tags <role>` from the laptop; this file + skills go live via symlink (`~/.agents/` → the repo), no extra step.

Quick-fix-and-forget directly on the live VPS (`sudo apt install X`, hand-edited `~/.bashrc`, manual `gh auth login`, ad-hoc cron entry, …) is **forbidden as a final state** — it creates phantom "why is this broken again?" cycles after the next rebuild. A live-VPS edit is acceptable only as a temporary patch; the durable fix must land in the repo before the work is done.

### Docs ship with infra

Anything that touches user-facing behavior — an integration, credential workflow, runbook step, recovery procedure, command flow, naming convention — gets its matching doc in `docs/` updated in the **same commit** as the code change. The rule: *if `docs/` and the running system disagree, the system is right and the doc is a bug.* Fix it together, or delete the doc if it's no longer accurate. Stale docs are worse than no docs.

The most-touched docs by change type:

| Change | Doc |
|---|---|
| Integration added / replaced (Tailscale, GitHub, Hetzner, …) | the named doc (`docs/<name>.md`) |
| Provisioning flow / Ansible role behavior | `docs/provisioning.md` |
| Failure-mode handling | `docs/recovery.md` |
| Encrypted secret added or rotated | `docs/secrets.md` + the relevant integration doc |
| Naming or path rename | grep across `docs/` + every `*/README.md` |

## Build on what we learn — always be improving

The devbox, its docs, and these agent rules are never "done." Whenever you spot a chance to make the workflow better — a repetitive manual step worth scripting, a recurring mistake worth a guardrail, something that belongs in an `AGENTS.md`/`CLAUDE.md` or a skill, a docs structure that's drifting, a convention worth codifying — **propose it to the user and ask their opinion.** Don't silently route around friction; don't unilaterally restructure load-bearing things either. Surface the idea, explain the *why*, and let them decide. The goal is compounding: every session should leave the system a little sharper than it found it, and key decisions should end up written down where they're easy to find again.

## Tools

| Tool | What for |
|---|---|
| **mise** | Per-project Node/Bun/pnpm versions + tasks + env (`.mise.toml`). Always prefer `mise run <task>` over guessing commands. |
| **Zellij** | Workspace persistence. Per-project `zellij.kdl` layout. |
| **Claude Code** + **Codex CLI** | Both honor this AGENTS.md and the shared skills. |
| **Claude Squad** (`cs`) | TUI for parallel agents on git worktrees. |
| **Tailscale** | Private mesh. Use tailnet IPs (`100.x.y.z`), never the public IP. |
| **`wt`** | Worktree + PR + merge wrapper (see below). Use this instead of raw `git worktree` / `gh pr` / other git related commands. |
| **`gh`** | GitHub CLI. Use for git related actions not available through `wt`. |
| **`devbox-scaffold`** | Generate `.mise.toml` + `zellij.kdl` for a new repo. Invoked via the [`clone-repo`](skills/clone-repo/SKILL.md) skill, which inspects the repo and proposes the right args before running. |
| **`devbox-reprov`** | Re-run the Ansible playbook locally on the devbox (`git pull` then `ansible-playbook --connection=local`). Use this after editing a role/chezmoi source to apply changes without needing the laptop. Pass `--check --diff` for dry-run, `--tags <role>` for a narrow re-run. |
| **`devbox-doctor`** | Read-only health check for the box (binaries on PATH, Tailscale + SSH, docker, agent-layer symlinks, repo cleanliness, free disk + memory). Run after a `devbox-reprov` to smoke-test, or any time things feel off. Exit code = number of failures. |
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
| `wt prune` | Manually sweep merged-PR worktrees across all repos. **Not** automated — use the session-aware `/prune` skill instead for considered cleanup. |
| `wt help` | Full reference. |

**Always** use `wt new` instead of `git worktree add`. **Always** use `wt pr` / `wt merge` instead of `gh pr create` / `gh pr merge`. They handle sync, rebase, and cleanup that's easy to forget manually.

### Shared-branch work and commit discipline

Worktrees are the default for anything that's a feature in its own right. But not all work is a feature — small, scattered chores (a doc tweak, a lint fix, a config bump, a one-line cleanup) don't each deserve a branch. For that kind of work we often have **multiple agents working concurrently on the same branch** (`main`/`master`). That makes the working tree a shared space where changes you didn't make can show up at any moment, so:

- **Never commit blindly.** No `git add -A`, no `git add .`, no `git commit -a`. Another agent's in-flight edits live in the same tree, and a blind "take all" sweeps them into your commit. Always stage explicitly by path (`git add <file> …`) and run `git status` / `git diff --staged` to confirm you're committing only what you intend — nothing more.
- **Prefer many small, targeted commits** over one fat one. Each commit should be a single coherent change with its own focused message. Small commits are easier to review, revert, and reason about, and they minimize the window where your staged set could collide with a co-worker agent's.

### Clean before you push

Code goes to remote **clean** — never push raw, unchecked work. Before `wt pr` (or any push), run the working repo's quality gate: **format, lint, and typecheck**, plus tests where the change warrants them. The exact commands are per-repo and defined in that repo's dev contract (its `.mise.toml` tasks / `CLAUDE.md`) — discover and run *those*, don't guess. For kost that's `oxfmt` (format) + `oxlint` (lint) + `tsgo` typecheck, all exposed as mise tasks. Fix what they flag before pushing; remote is not the first feedback loop. Markdown/doc-only changes don't need a typecheck, but still apply whatever formatting the repo enforces.

## Repository sync

The VPS does **not** auto-pull repos on a schedule. Freshness is enforced at the moments where it matters:

- `wt new` fetches origin and branches from `origin/<default>` — the new worktree always starts from current state, no manual pull needed.
- `wt pr` fetches and rebases — feature branch is current with `origin/<default>` before the PR opens. Conflicts surface to you as a normal rebase pause; resolve, `git rebase --continue`, re-run `wt pr`.
- `wt merge` pulls the default branch forward after merge, leaving the main checkout current.
- Worktree cleanup is **not** automated (no cron). A worktree whose PR merged outside `wt merge` lingers until you prune it deliberately via the `/prune` skill — which checks for live sessions and uncommitted work first, so it never orphans a session you're still using.

If you find yourself wanting to `git pull` on a default branch manually, you don't need to — the next `wt new` or `wt merge` handles it. However, you can do it, if needed.

## Worktree environment files

Gitignored env files (`.env`, `.env.local`, `apps/*/.env*`, …) **do not follow** worktree creation — they live in whichever checkout originally created them. A new worktree that needs them will look fine to git and fail opaquely the first time you run the dev contract.

When you start work in a worktree, before running tasks:

1. **Find them in the source checkout** —
   `git -C ~/code/<repo> ls-files --others --ignored --exclude-standard | grep -E '(^|/)\.env'`.
2. **Mirror anything that exists** into the same path in the new worktree. Without this the dev contract throws at boot (e.g. zod "Invalid env" on Expo, "DATABASE_URL is required" on drizzle-kit) or runs but talks to the wrong host.
3. **Sanity-check host-pointing values** (`*_BASE_URL`, anything with an IP or `localhost`). If the env was authored on a laptop and you're now on the devbox, swap LAN IPs for the devbox's Tailscale MagicDNS FQDN so phones / other tailnet peers can reach the dev server.
4. **When you discover a new env file pattern that isn't yet listed** in that repo's `CLAUDE.md` / `AGENTS.md`, **add the concrete list there** (source path → destination path, plus any host-substitution notes). Per-repo facts belong in per-repo agent files; this section documents only the universal principle. The next session shouldn't have to re-derive it.

Same applies in reverse for new env vars added during a session — if you add one to the worktree's env file, also add it to `.env.example` so other checkouts pick it up.

## Code quality — modularize, reuse, refactor

Keep the code clean, predictable, and well-bounded across every repo:

- **Componentize / modularize by default.** Give each unit a clear, single responsibility and a sane boundary. Prefer small, named, reusable pieces over sprawling inline blocks.
- **Reuse before rebuild.** Before writing something, look for an existing component / module / helper that already does it. Compose what's there rather than duplicating.
- **The rule of two.** The first time you write something, inline is fine. The *second* time you find yourself writing the same shape (a layout, a button pattern, a data transform, a hook), extract it into a shared component/module and route both callers through it. Don't wait for a third.
- **Always look for refactor opportunities** — even outside the immediate task. If you spot duplication, a leaky boundary, or a pattern that wants a name, call it out and (if cheap) fix it.
- **But don't over-engineer.** No abstractions for a single use case, no premature generality, no framework-building. Three similar lines beat a wrong abstraction. Extract when the duplication is *real and repeated*, not hypothetical. The goal is clean and predictable, not clever.

Per-repo specifics (architecture layers, naming, file-size limits) live in that repo's `CLAUDE.md` and win where they conflict — this is the cross-repo baseline.

## Conventions

- **Don't `sudo`** unless necessary. `fum4` has NOPASSWD sudo but day-to-day work doesn't need it.
- **Don't expose anything to the public internet.** All inbound traffic except SSH is firewalled; reach dev servers over Tailscale.
- **Per-repo dev contract**: each repo's `.mise.toml` (tasks) and `zellij.kdl` (workspace) are the source of truth for "how to run this project." Add them when scaffolding a new repo. Every `.mise.toml` should define a `[tasks.setup]` — the first-time install command (`pnpm install`, `cargo fetch`, etc.). The `repos` Ansible role runs it for every cloned repo on every fresh provision, so a rebuilt devbox comes up with all dependencies installed.
- **The VPS is ephemeral.** Anything not in git or in `~/code/devbox/` is at risk on rebuild. Don't store load-bearing state outside these. See "Source of truth" above for where each kind of change belongs.
- **Long-running processes** go in Zellij tabs, not bare SSH sessions. Otherwise they die when SSH drops.
- **Globals via mise, not npm/pnpm**: don't install global npm/pnpm packages. Add them as `[tools]` in a repo's `.mise.toml`.
- **Don't edit chezmoi-managed files directly**: `~/.bashrc`, `~/.config/zellij/config.kdl`, `~/.local/bin/*`. Edit `~/code/devbox/chezmoi/` and `chezmoi apply` (or run the ansible role).
- **New tools go through Ansible**: don't `apt install X` ad-hoc. Add a role in `~/code/devbox/ansible/roles/` so the VPS stays reproducible.
- **Verify latest version before installing or pinning.** Before adding any versioned dependency — apt / pip / npm / cargo / brew package, GitHub Action, container image, binary release — check the *current* latest stable. Use `gh api repos/<owner>/<repo>/releases/latest --jq '.tag_name'`, the package registry, or the project's release page. Don't lean on remembered version numbers; the gap between "I last checked" and "now" is usually months and sometimes years. Pin to actual-latest in the same commit, and re-check on every revisit.
- **GitHub identity is age-encrypted**: this VPS's GitHub SSH key (`~/.ssh/github-ssh`) and the `gh` CLI auth come from `ansible/secrets/github-*.age`, decrypted on the laptop during provisioning. Don't manually `gh auth login` or `ssh-keygen` for GitHub — those changes get clobbered on re-provision and the devbox loses its persistent identity. See `~/code/devbox/docs/github.md` for the rotation procedure.

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
| Clone + set up a new repo | use the `clone-repo` skill — clones from `github.com/fum4/<repo>` by default, proposes `devbox-scaffold` args, waits for user confirmation |
| Apply devbox changes (role/chezmoi/skill/AGENTS.md edits) | `devbox-reprov` (or `devbox-reprov --check --diff` for a dry-run; `--tags <role>` for one role) |
| Health-check the box | `devbox-doctor` |
| See active sessions + worktrees | `/sessions` skill (or the `claude-sessions` helper for raw facts) |
| List available skills | `/help` skill |

For when to use a worktree (and when not), the `parallel-work` skill in `~/.agents/skills/parallel-work/SKILL.md` has the full decision tree. For onboarding a new repo onto the devbox, the `clone-repo` skill walks through clone → inspect → confirm → scaffold.
