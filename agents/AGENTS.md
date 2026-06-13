# Agent instructions for the devbox

You are running on a personal Hetzner Cloud VPS (Debian 12) -- the devbox -- used as a remote dev environment for multiple projects. The owner drives sessions from a phone via Claude's Remote Control feature or by SSHing in from a laptop.

The VPS itself is provisioned declaratively from `~/code/devbox` (Ansible + chezmoi). When something looks misconfigured, look there first.

## Session start ritual

At the very start of every new session — before addressing the user's first request — do two things, in order:

1. **Greet in an original, funny persona.** Pick a *different* voice each time and commit to it for a line or two — a medieval king, a hype rapper, a noir gumshoe, a pirate, a Shakespearean bard, a breathless sportscaster, a 1950s radio announcer, whatever feels fresh. Land the bit, then drop it. Don't reuse a persona you can tell you've used recently; keep it surprising.
2. **Report the lay of the land.** Show the user every active Claude session and git worktree, each with a one-line "what it's about" (use the `/sessions` skill — don't trust session names alone, peek at the actual cwd/worktree/transcript). This way the user always knows what's running before diving in.

Then proceed with the user's actual request. (This ritual is global across all repos, not just devbox.)

## Session & context hygiene — proactively suggest when to split or reset

A session's context is a working resource, not a dumping ground. **Continuously watch for the moment a session has outgrown its current shape, and proactively say so** — don't wait to be asked. The user wants to be told *when* to start a new session, branch a worktree, `/clear`, or park/kill the current one, with a recommendation and the reasoning.

Flag it (with a concrete suggestion) when you notice any of:

- **Topic shift.** The next piece of work is a *different concern* from what filled the context (e.g. you just did infra + a long research thread, and now it's time to write feature code). A fresh, lean session beats dragging unrelated context along.
- **New feature-sized work.** Anything multi-commit / real blast radius → propose a `/new-work-session` (clarifies the task, then cuts its own worktree) rather than starting code in a long-running chat. Tie the new session to its brief (e.g. an ADR or plan doc).
- **Context bloat.** The conversation has grown long or wandered across many subjects, so responses risk getting slower / less focused → suggest `/clear` (same task, clean slate) or a new session (different task).
- **Clean stopping point.** The current session's deliverables are all committed/merged and nothing is in-flight → say so and recommend park (reversible, keeps the conversation) vs kill (durable output already captured elsewhere, e.g. in an ADR/PR).
- **Two sessions converging on one repo** → worktree, always (the one non-negotiable from the branch/PR workflow).

Make it a **recommendation, not a unilateral action**: name the move (new work session / `/clear` / park / kill / worktree), the *why*, and let the user decide. Prefer the reversible option when unsure (park over kill, worktree over shared branch). This complements — does not replace — the "Postponed work goes in `TODO.md`" and "Build on what we learn" rules below.

## Layout

- **Repos**: `~/code/<project-name>/` (e.g. `~/code/tipso`). Each is its own git repo.
- **VPS infra source**: `~/code/devbox`.
- **Cross-agent home**: `~/code/devbox/agents/` — `./AGENTS.md` (this file) and `./skills/` (our custom skills, loaded on demand). Third-party **vendored skills** are pinned in `~/code/devbox/easyskills/skills.toml` and managed with `easyskills`; both kinds land as symlinks in `~/.agents/skills/`. See [`docs/skills.md`](../docs/skills.md).
- **Agent sessions**: each is a systemd user unit `claude@<name>.service` (durable, isolated, phone-driveable). Spawn with `claude-spawn`, restore after a reboot with `claude-restore`. See [`docs/sessions.md`](../docs/sessions.md).
- **Dev servers**: per-project `process-compose` stacks, on-demand, run via `/serve`.
- **Dashboards**: `zj <project>` opens a *disposable* Zellij view onto a project's live sessions + dev servers — it hosts nothing, so killing it loses nothing.

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

> ### 🛑 STOP — before scaffolding any repo's secrets or infra, read the doc first
>
> There is **one canonical pattern** for how every repo handles its secrets
> (per-repo age key, `secrets/*.age`, `tools/secrets.sh`, `mise run secrets:*`)
> and its infra (Terraform + R2 state, `<repo>-backup` bucket, `<repo>-terraform-state`
> token). It is written down in **[`docs/repo-secrets.md`](../docs/repo-secrets.md)**.
>
> **Always open and follow that doc** when creating/cloning a repo or touching its
> `secrets/` or `terraform/`. Do **not** reconstruct the pattern from memory and do
> **not** copy another repo's wrapper blindly — that is precisely how `ops` drifted
> onto the wrong pattern (it copied the devbox-internal `bin/devbox-tf` + repo-root
> `secrets.local` style instead of the repo pattern) and had to be rebuilt. The
> reference impls are **tipso** and **ops**; copy tipso's `tools/secrets.sh` +
> `secrets/` verbatim and adjust the manifest. This rule generalises: when a
> doctrine doc exists for what you're about to scaffold, read it before you start.

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

### Postponed work goes in the repo's `TODO.md`

A repo's root `TODO.md` is the **owner's attention queue** — the list of things we consciously did *not* tackle now and that **need the owner to come back to** (a decision, a paid signup, a manual step, a deferred follow-up). Its single purpose is *don't let the owner forget*: they read it to see what's waiting on them, and they want to clear it ASAP.

When you postpone something, record it in the root `TODO.md` of the repo it belongs to (create the file if absent) — don't let it live only in chat, a commit message, or your own memory; those don't survive the session. Scope it to the right repo (kost work → `kost/TODO.md`, devbox work → `devbox/TODO.md`).

**Keep entries short and owner-facing**: what's waiting, why it was deferred, and the first concrete step — a few lines each, not pages. `TODO.md` is **not** a planning document: don't dump implementation plans, design analyses, or build phases there (those belong in the conversation, a handoff doc, or a design doc under `docs/`). Keep it honest — check items off or delete them when done; a stale `TODO.md` defeats its purpose.

## Tools

| Tool | What for |
|---|---|
| **mise** | Per-project Node/Bun/pnpm versions + tasks + env (`.mise.toml`). Always prefer `mise run <task>` over guessing commands. |
| **systemd (user) + dtach** | Hosts agent sessions: `claude@<name>.service` holds a `dtach` PTY. Durable across SSH drops/reboots, isolated per-session. Managed via `claude-spawn` / `claude-restore` / `claude-park`, not by hand. See [`docs/sessions.md`](../docs/sessions.md). |
| **Zellij** | **Disposable dashboard viewer** (`zj <project>`) onto live sessions (`dtach -a`) + dev servers. Hosts nothing long-lived — not a process supervisor. |
| **Claude Code** + **Codex CLI** | Both honor this AGENTS.md and the shared skills. |
| **Claude Squad** (`cs`) | TUI for parallel agents on git worktrees. |
| **Tailscale** | Private mesh. Use tailnet IPs (`100.x.y.z`), never the public IP. |
| **`wt`** | Worktree + PR + merge wrapper (see below). Use this instead of raw `git worktree` / `gh pr` / other git related commands. |
| **`gh`** | GitHub CLI. Use for git related actions not available through `wt`. |
| **`devbox-scaffold`** | Generate `.mise.toml` + `zellij.kdl` for a new repo. Invoked via the [`clone-repo`](skills/clone-repo/SKILL.md) skill, which inspects the repo and proposes the right args before running. |
| **`easyskills`** | Vendored-skills manager (our own tool, built from `~/code/easyskills`). Manifest + commit pins live in `~/code/devbox/easyskills/skills.toml` (`$EASYSKILLS_HOME`); add/update/patch flows + security policy in [`docs/skills.md`](../docs/skills.md). Installs always need explicit user confirmation + a read of the fetched SKILL.md. |
| **`devbox-reprov`** | Re-run the Ansible playbook locally on the devbox (`git pull` then `ansible-playbook --connection=local`). Use this after editing a role/chezmoi source to apply changes without needing the laptop. Pass `--check --diff` for dry-run, `--tags <role>` for a narrow re-run. |
| **`devbox-doctor`** | Read-only health check for the box (binaries on PATH, Tailscale + SSH, docker, agent-layer symlinks, repo cleanliness, free disk + memory). Run after a `devbox-reprov` to smoke-test, or any time things feel off. Exit code = number of failures. |
| **`bin/devbox-tf`** | Terraform for the VPS itself (`terraform/devbox/` — server, stable primary IP, firewall). **Laptop-only** (lane-2 creds live there; the box can't rebuild itself) — on the box, limit yourself to editing `.tf` files + `mise run tf:check`. Runbooks: [`docs/terraform.md`](../docs/terraform.md). |
| **ripgrep** (`rg`), **fd**, **jq** | Search and JSON parsing. Prefer over `grep -r` / `find` / `python -m json.tool`. |
| **process-compose** | Per-project dev-server stacks (API, Metro, infra) — on-demand, restart-fresh, run via `/serve` on a `pc-<project>.sock` UDS. Also fine for headless backing services (Postgres, Redis, workers). |
| **ntfy** | Push notifications to phone (installed dormant — `curl -d "msg" ntfy.sh/$NTFY_TOPIC` once a topic is wired). |
| **chezmoi** | Dotfile manager. Source lives in `~/code/devbox/chezmoi/`. |

## Branch / PR / merge workflow

Use the `wt` wrapper, not raw git/gh, for the worktree → PR → merge lifecycle:

| Command | Effect |
|---|---|
| `wt new <task>` | Branch a worktree from **`origin/<default>`** (fetches first). Creates `../<repo>-<task>` with branch `<task>`. |
| `wt pr [gh-args…]` | Fetch + rebase on `origin/<default>` + `git push --force-with-lease` + `gh pr create`. Pauses on conflicts. |
| `wt merge [strategy]` | Merge the current branch's PR (default `--squash`) + delete remote & local branch + remove worktree + pull `<default>` forward. Also works from a main checkout sitting on the feature branch (merges, then returns the checkout to `<default>`). |
| `wt rm <task> [--force]` | Remove a worktree. Refuses unless the PR is MERGED (or `--force`). |
| `wt wip [path]` | One-shot WIP report for a checkout: branch, uncommitted/stashes, unpushed, PR state, gitignored env files. Used by `/park`, `/kill`, `/prune`. |
| `wt env [task]` | Mirror gitignored env files from the main checkout into a worktree (never overwrites). Runs automatically at the end of `wt new`; re-run by hand when env files change. |
| `wt help` | Full reference. |

`wt` is the deterministic core; the judgment layer lives in skills. List worktrees with `git worktree list`. To clean up stale worktrees use the session-aware **`/prune`** skill (parks live sessions, checks for uncommitted work). To spawn a worktree-backed session use **`/new-work-session`**. Both build on the commands above rather than duplicating the git plumbing.

**Always** use `wt new` instead of `git worktree add`. **Always** use `wt pr` / `wt merge` instead of `gh pr create` / `gh pr merge`. They handle sync, rebase, and cleanup that's easy to forget manually.

### When to use a worktree — judge the size, propose first

No decision tree; one judgment call: **is this big enough to be a feature?**

- Quick bug fix, doc tweak, config bump, small chore → do it directly on the default branch (shared-branch discipline below applies).
- A feature, a refactor with real blast radius, anything multi-commit or that will run alongside other work → worktree via `wt new`.
- **Propose before creating.** Say "this looks worktree-sized — branch a worktree?" and let the user confirm; they may prefer quick-and-dirty on the default branch. Don't silently `wt new`.
- Two sessions about to touch the same repo at once → worktree, always — that's the one non-negotiable (merge headaches otherwise).

If a worktree's dev contract fails on boot (zod "Invalid env", missing `DATABASE_URL`), it's almost always env files — `wt env` mirrors them (and `wt new` already does it); see "Worktree environment files" below.

### Shared-branch work and commit discipline

Worktrees are the default for anything that's a feature in its own right. But not all work is a feature — small, scattered chores (a doc tweak, a lint fix, a config bump, a one-line cleanup) don't each deserve a branch. For that kind of work we often have **multiple agents working concurrently on the same branch** (`main`/`master`). That makes the working tree a shared space where changes you didn't make can show up at any moment, so:

- **Never commit blindly.** No `git add -A`, no `git add .`, no `git commit -a`. Another agent's in-flight edits live in the same tree, and a blind "take all" sweeps them into your commit. Always stage explicitly by path (`git add <file> …`) and run `git status` / `git diff --staged` to confirm you're committing only what you intend — nothing more.
- **Prefer many small, targeted commits** over one fat one. Each commit should be a single coherent change with its own focused message. Small commits are easier to review, revert, and reason about, and they minimize the window where your staged set could collide with a co-worker agent's.

### Clean before you push

Code goes to remote **clean** — never push raw, unchecked work. Before `wt pr` (or any push), run the working repo's quality gate: **format, lint, and typecheck**, plus tests where the change warrants them. The exact commands are per-repo and defined in that repo's dev contract (its `.mise.toml` tasks / `CLAUDE.md`) — discover and run *those*, don't guess. For kost that's `oxfmt` (format) + `oxlint` (lint) + `tsgo` typecheck, all exposed as mise tasks. Fix what they flag before pushing; remote is not the first feedback loop. Markdown/doc-only changes don't need a typecheck, but still apply whatever formatting the repo enforces.

### Keep CI green — every repo, always

`main` stays green at all times, in **every** repo (devbox included). A red CI run is a bug, not background noise — it blinds the next person to real failures and makes the pipeline worthless as a signal.

- **Never push work that reds CI.** The local quality gate above exists precisely so the first red isn't on the remote. If a push goes red, fixing it is the immediate next task — before the work you were about to do.
- **Never merge onto red.** Don't merge a PR with a failing required check, and don't admin-merge "to fix later" — *later* is how `main` rots red for days.
- **A pre-existing red `main` is a P0.** If you find it already broken (not your change), surface it and fix it — or get the owner's call — before stacking more work on top.
- **CI must test what actually runs.** If CI is green but the real target fails (or vice-versa), the check is lying — fix the *mismatch* (install the same deps/versions the target has), never tune the check to a dishonest green. (E.g. CI installing `ansible-core` while the box runs full `ansible` — the roles' collections didn't resolve in CI though they work in production.)

### Keep docs current — every repo, always

Docs are part of the change, not a follow-up. A README, doc, or comment that contradicts the code is a bug — like a red CI run, it quietly misleads the next person. **If a doc/README/comment and the code disagree, the code is right and the doc is the defect.** This holds in **every** repo, not just devbox.

- **Update the doc in the same commit as the code that dates it.** Add a workspace app, rename a path, change a command/flow → fix the doc that describes it right then. "Later" is how an `apps/README.md` ends up listing 2 of 5 apps.
- **When you touch a file, glance at the docs nearest it** — the README in the directory you're editing, the doc a behavior is described in. Correct drift you spot even if it predates your change (cheap fixes now; flag bigger ones).
- **Structural truth especially.** Docs that *enumerate reality* — an `apps/` / `packages/` README, a module index, a tools table — must match what's actually there. They rot silently and mislead newcomers most.

(devbox's own infra docs carry a stronger same-commit obligation — see "Docs ship with infra" above. This is the cross-repo floor.)

## Repository sync

The VPS does **not** auto-pull repos on a schedule. Freshness is enforced at the moments where it matters:

- `wt new` fetches origin and branches from `origin/<default>` — the new worktree always starts from current state, no manual pull needed.
- `wt pr` fetches and rebases — feature branch is current with `origin/<default>` before the PR opens. Conflicts surface to you as a normal rebase pause; resolve, `git rebase --continue`, re-run `wt pr`.
- `wt merge` pulls the default branch forward after merge, leaving the main checkout current.
- Worktree cleanup is **not** automated (no cron). A worktree whose PR merged outside `wt merge` lingers until you prune it deliberately via the `/prune` skill — which checks for live sessions and uncommitted work first, so it never orphans a session you're still using.

If you find yourself wanting to `git pull` on a default branch manually, you don't need to — the next `wt new` or `wt merge` handles it. However, you can do it, if needed.

## Worktree environment files

Gitignored env files (`.env`, `.env.local`, `apps/*/.env*`, …) **do not follow** worktree creation — they live in whichever checkout originally created them. A new worktree that needs them will look fine to git and fail opaquely the first time you run the dev contract.

**`wt env` does the mechanical part**: it mirrors every gitignored `.env*` file from the main checkout into the worktree (same relative path, never overwriting), and runs automatically at the end of `wt new`. Re-run it by hand (`wt env` from inside the worktree, or `wt env <task>` from main) when env files were added after the worktree was created.

What stays on you (judgment, not mechanics):

1. **Sanity-check host-pointing values** (`*_BASE_URL`, anything with an IP or `localhost`) — `wt env` flags files containing them but won't rewrite. If the env was authored on a laptop and you're now on the devbox, swap LAN IPs for the devbox's Tailscale MagicDNS FQDN so phones / other tailnet peers can reach the dev server.
2. **When you discover a new env file pattern that isn't yet listed** in that repo's `CLAUDE.md` / `AGENTS.md`, **add the concrete list there** (source path → destination path, plus any host-substitution notes). Per-repo facts belong in per-repo agent files; this section documents only the universal principle. The next session shouldn't have to re-derive it. (Note: `wt env` collapses fully-ignored *directories* — an env file living inside one, e.g. `config/secrets/.env`, won't be auto-mirrored; that's exactly the kind of repo quirk to document per-repo.)

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
- **Per-repo dev contract**: each repo's `.mise.toml` (tasks) and, for its dev servers, a `process-compose.yaml` (the stack `/serve` runs) are the source of truth for "how to run this project." Add them when scaffolding a new repo. Every `.mise.toml` should define a `[tasks.setup]` — the first-time install command (`pnpm install`, `cargo fetch`, etc.). The `repos` Ansible role runs it for every cloned repo on every fresh provision, so a rebuilt devbox comes up with all dependencies installed.
- **The VPS is ephemeral.** Anything not in git or in `~/code/devbox/` is at risk on rebuild. Don't store load-bearing state outside these. See "Source of truth" above for where each kind of change belongs.
- **Long-running processes get a real supervisor, never a bare SSH session or a Zellij pane** (both die on disconnect / viewer-death). Agent sessions → systemd via `claude-spawn`; dev servers → process-compose via `/serve`. See [`docs/sessions.md`](../docs/sessions.md).
- **Name new sessions for the work, never a counter.** When spawning a session (`/new-chat-session`, `/new-work-session`, `claude-spawn`), do **not** auto-generate generic names like `kost-1`, `kost-2` — they make the session list impossible to map back to what each is for. If the purpose is clear from context, name it after that (`reports`, `ocr-eval`, `auth-refactor`); if it isn't, **ask the user what to call it** before spawning. A unique, descriptive name is required (it's the systemd instance, the Remote-Control name, and the dashboard tab — one name, everywhere).
- **When a step is the owner's to do in a web dashboard, spell it out exactly — leave nothing to their discretion.** Any time the owner must configure something themselves in a provider UI (Hetzner, Cloudflare, Tailscale, GitHub, Vercel, …), give precise click-by-click instructions: the exact console URL/path, the exact button and field names, the exact values to enter (token name, the specific scope/permission to pick, bucket name, region, expiry), and exactly what to copy out and where to save it. No "create a token with the appropriate scope" hand-waving — name the scope. Number the steps. Assume the owner wants to follow, not decide.
- **Tailnet devices join *tagged*, via an OAuth client — never a standing key or a console tag.** Every device joins as `tag:<device>` (tailnet-owned, no key expiry, ACL-managed by tag), provisioned by a per-device Tailscale **OAuth client** (Auth Keys → Write, scoped to that tag) that mints a *fresh single-use* key each provision — the Ansible `tailscale` role for the devbox, the TF wrapper (`bin/<repo>-tf`) for Terraform/cloud-init boxes. Hand-tagging a device in the console (*Edit ACL tags*) or committing a static auth key is **drift**; a personal (untagged) join is wrong for a server (it expires). The OAuth `client_secret` is age-encrypted next to its owner; the `client_id` is non-secret. Full pattern: [`docs/tailscale-provisioning.md`](../docs/tailscale-provisioning.md). Refs: the devbox `tailscale` role; jarvis `bin/jarvis-tf`.
- **Globals via mise, not npm/pnpm**: don't install global npm/pnpm packages. Add them as `[tools]` in a repo's `.mise.toml`.
- **Don't edit chezmoi-managed files directly**: `~/.bashrc`, `~/.config/zellij/config.kdl`, `~/.config/systemd/user/claude@.service`, `~/.local/bin/*`. Edit `~/code/devbox/chezmoi/` and `chezmoi apply` (or run the ansible role).
- **New tools go through Ansible**: don't `apt install X` ad-hoc. Add a role in `~/code/devbox/ansible/roles/` so the VPS stays reproducible.
- **Verify latest version before installing or pinning.** Before adding any versioned dependency — apt / pip / npm / cargo / brew package, GitHub Action, container image, binary release — check the *current* latest stable. Use `gh api repos/<owner>/<repo>/releases/latest --jq '.tag_name'`, the package registry, or the project's release page. Don't lean on remembered version numbers; the gap between "I last checked" and "now" is usually months and sometimes years. Pin to actual-latest in the same commit, and re-check on every revisit.
- **GitHub identity is age-encrypted**: this VPS's GitHub SSH key (`~/.ssh/github-ssh`) and the `gh` CLI auth come from `ansible/secrets/github-*.age`, decrypted on the laptop during provisioning. Don't manually `gh auth login` or `ssh-keygen` for GitHub — those changes get clobbered on re-provision and the devbox loses its persistent identity. See `~/code/devbox/docs/github.md` for the rotation procedure.
- **Secrets: encrypted-at-rest always, stored with their owner.** Never leave a secret existing *only* as gitignored plaintext in a working tree — that's the same drift trap as a hand-edited live config (a rebuild or laptop loss wipes it). The rule is about *encryption*, not a single location. Two layers: (1) **root of trust = your password manager**, holding all provider account logins + 2FA recovery codes *and* the age private keys; (2) the **secrets themselves are age-encrypted in git, next to whoever owns them** — the *box's own* identity secrets (GitHub/Tailscale/Expo) in `devbox/ansible/secrets/*.age` under the devbox key; a *repo's* deploy/dev secrets **in that repo**, under that repo's own key (self-contained + contained blast radius). The devbox's job for a repo is to *deliver its age key* to the box, not to store its secrets. **The canonical repo pattern (per-repo age key + `secrets/*.age` + `tools/secrets.sh` + `mise run secrets:*`) is [`docs/repo-secrets.md`](../docs/repo-secrets.md) — read it before scaffolding a repo's secrets.** Full model: [`docs/secrets.md`](../docs/secrets.md) (the devbox's own identity secrets) + [`docs/repo-secrets.md`](../docs/repo-secrets.md) (every other repo).
- 🔑 **NEVER tell the owner to save a secret in Bitwarden — this is a recurring drift, stop doing it.** When you walk the owner through obtaining *any* credential (API key, OAuth client secret, signing key/`.p8`, DB password, webhook secret, token of any kind), its destination is **always the repo's age-encrypted secrets** (`secrets/*.env` → `mise run secrets:encrypt` → `secrets/*.age`), and **the agent does the encrypting** — the owner just reads the value off the provider screen and pastes it (or you read it). **Bitwarden / the password manager holds EXACTLY three kinds of thing and nothing else: (1) the age *private keys* (the master keys that decrypt everything), (2) provider *account* logins, (3) 2FA recovery codes.** Before you type "save this in Bitwarden / your password manager," verify it's one of those three — an API token/secret is *never* one of them, so it goes in `secrets/*.age`. Don't even offer Bitwarden as a "temporary holding spot." Canonical model: [`docs/repo-secrets.md`](../docs/repo-secrets.md) + [`docs/secrets.md`](../docs/secrets.md).
- **Provision infrastructure with Terraform, always — never click-ops.** Every piece of cloud infra — servers, firewalls, networks, volumes, DNS records, object-storage buckets, across *every* provider (Hetzner, Cloudflare, …) and *every* repo — is declared in `.tf` and applied through that repo's TF wrapper. Hand-creating or hand-editing infra in a provider's web console is **forbidden as a final state**, exactly like a hand-edited live config: it's drift that dies on the next rebuild and orphans real resources. A console action is acceptable *only* for the documented out-of-band bootstrap (e.g. the first R2 state bucket) or as a temporary patch — the durable definition must land in Terraform before the work is done. This pairs with the state/creds rule below (TF state in R2, TF creds age-in-git).
- **Infra state & creds are global doctrine — age-in-git, keys in Bitwarden, state/backups in R2.** These house rules apply to *every* repo, not just devbox (a repo may add its own specifics on top). Terraform **state is never local-only**: it lives in a private, per-repo **R2** bucket (S3 backend) so a lost laptop/devbox never orphans live infra; the state bucket is bootstrapped out-of-band. TF creds are stored like every other secret — **age-encrypted in git** next to their owner (devbox: `ansible/secrets/hetzner-token.age` + `r2-devbox-state.age`, decrypted *in memory* by `bin/devbox-tf` on the laptop) — they differ from lane-1 identity secrets only in *consumer* (Terraform vs Ansible), never in storage. **The password manager holds ONLY age keys + provider account logins/2FA — never individual API tokens, and no token ever lives only as gitignored plaintext.** Each repo owns its own `infra/terraform/` + state bucket; the devbox provisions only itself (`terraform/devbox/`). **Before minting any new credential/token/key/state store, walk the 6-question checklist** in [`docs/secrets.md`](../docs/secrets.md) → "Minting anything new?" — every drift incident so far came from skipping one of its questions. Full model: same doc → "Global doctrine"; reference impl: tipso `infra/terraform/` + its `docs/runbooks/`.

## Common operations

| Goal | How |
|---|---|
| Open a project dashboard | `zj <project>` (disposable view: live agents + dev servers) |
| Detach from a dashboard | `Ctrl+O` then `d` (a dtach pane: `Ctrl+\`) |
| Spawn an agent session | `claude-spawn --name <name> --cwd <dir>` |
| Restore sessions after a reboot | `claude-restore` (list) · `claude-restore <name>` / `--all` |
| Park (stop) a session, keep the conversation | `claude-park <name>` (with WIP checks: the `/park` skill) |
| Kill a session for good (+ its worktree) | `claude-kill <name> [--rm-worktree]` (with WIP checks: the `/kill` skill) |
| List dashboards | `zellij ls` |
| Run a task | `mise run <task>` (after `cd <repo>`) |
| List tasks for current repo | `mise tasks` |
| Start new unrelated work | `wt new <task>` (creates worktree branched from `origin/<default>`) |
| Open a PR | `wt pr` (rebase + push + `gh pr create`) |
| Merge + clean up | `wt merge` |
| Clone + set up a new repo | use the `clone-repo` skill — clones from `github.com/fum4/<repo>` by default, proposes `devbox-scaffold` args, waits for user confirmation |
| Apply devbox changes (role/chezmoi/skill/AGENTS.md edits) | `devbox-reprov` (or `devbox-reprov --check --diff` for a dry-run; `--tags <role>` for one role) |
| Change the VPS itself (server type, firewall, IP) | edit `terraform/devbox/*.tf` + `mise run tf:check`; apply happens on the laptop via `bin/devbox-tf` ([`docs/terraform.md`](../docs/terraform.md)) |
| Health-check the box | `devbox-doctor` |
| See active sessions + worktrees | `/sessions` skill (or the `claude-sessions` helper for raw facts) |
| List available skills | `/help` skill |
| Add a vendored (third-party) skill | `easyskills --global add github:<owner>/<repo> --include <skill>` → security-read it → commit `skills.toml` (policy: [`docs/skills.md`](../docs/skills.md)) |
| Update vendored skills | `easyskills --global outdated` → `easyskills --global update` → review diff → commit |

For onboarding a new repo onto the devbox, the `clone-repo` skill walks through clone → inspect → confirm → scaffold.
