# chezmoi/

User-level dotfile sources. Materialized into `$HOME` on the VPS by the `dotfiles` Ansible role.

## What this is

This directory is **chezmoi's source state** — a structured set of files that chezmoi translates into `$HOME` content with the right paths, permissions, and (optionally) templating. Editing a file here and re-applying chezmoi (`chezmoi apply`) propagates the change to the live `$HOME`.

## What chezmoi does

[chezmoi](https://www.chezmoi.io) is a dotfile manager. Given a *source directory* (this one) it produces files in `$HOME` based on filename prefixes. The translation is mechanical:

| Source filename | Becomes | Effect |
|---|---|---|
| `dot_X` | `.X` | The `dot_` prefix is replaced with a literal `.` |
| `executable_X` | `X` with `0755` | Adds the executable permission |
| `private_X` | `X` with `0600` (file) or `0700` (dir) | Owner-only permissions |
| `symlink_X` | `X` as a symlink to the file's contents | Source file body = literal target path |
| `encrypted_X` | `X` after decryption | Decrypted from age/gpg at apply time |
| `X.tmpl` | `X` after Go-template render | Per-machine variables substituted |
| `run_once_X.sh` | (runs once, never stored) | One-shot setup script |

Prefixes nest naturally: `private_dot_ssh/config` → `~/.ssh/config` with `0600` perms.

## What's here

```
chezmoi/
├── dot_bashrc                              → ~/.bashrc
├── private_dot_claude/      (private_ → ~/.claude gets mode 700; it holds credentials)
│   └── symlink_settings.json               → ~/.claude/settings.json   (symlink into agents/claude/)
├── dot_config/
│   └── zellij/
│       └── config.kdl                      → ~/.config/zellij/config.kdl
└── dot_local/
    └── bin/
        ├── executable_zj                   → ~/.local/bin/zj                  (chmod +x)
        ├── executable_wt                   → ~/.local/bin/wt                  (chmod +x)
        ├── executable_devbox-scaffold      → ~/.local/bin/devbox-scaffold     (chmod +x)
        ├── executable_devbox-reprov        → ~/.local/bin/devbox-reprov       (chmod +x)
        ├── executable_devbox-doctor        → ~/.local/bin/devbox-doctor       (chmod +x)
        ├── executable_claude-sessions      → ~/.local/bin/claude-sessions     (chmod +x)
        ├── executable_claude-spawn         → ~/.local/bin/claude-spawn        (chmod +x)
        └── executable_claude-park          → ~/.local/bin/claude-park         (chmod +x)
```

### `dot_bashrc`

Minimal interactive shell setup. **No human-ergonomics layer** (no fancy prompt, no `starship`, no `atuin`, no fuzzy history) — the VPS is agent-driven; humans rarely sit at this shell. What it does:

- Bail early for non-interactive shells (so `scp`/`rsync`/Ansible commands don't waste time on the rest)
- Standard `HISTSIZE` / `histappend` / `checkwinsize`
- Basic color support for `ls` / `grep`
- A minimal prompt (`user@host:cwd$`)
- PATH ordering: `~/.local/bin` and `~/bin` first
- mise activation (per-project tool versions, tasks, env vars)
- Sources `~/.bashrc.local` if present (escape hatch for machine-specific extras)

### `private_dot_claude/symlink_settings.json`

Materializes `~/.claude/settings.json` as a **symlink** into `~/code/devbox/agents/claude/settings.json` (not a copy). The file's body is the literal target path — that's how chezmoi's `symlink_` prefix works.

Why a symlink and not a copy: the Claude config is *agent-layer* state, so its canonical home is `agents/claude/` (see `agents/README.md`). chezmoi's job here is just to put a symlink at the right `~/.X` path. Editing `agents/claude/settings.json` is live immediately — no `chezmoi apply` needed for content changes; only re-run apply when adding a *new* file under `private_dot_claude/`.

### `dot_config/zellij/config.kdl`

Global Zellij preferences:

- `mouse_mode true` — click panes, drag splits, scroll
- `show_startup_tips false` — no noise
- `pane_frames true` — visible borders, easier to tell panes apart

Per-project layouts (which tabs / what they run) live in **each project's** `zellij.kdl`, not here. This file is preferences that apply globally.

### `dot_local/bin/executable_zj`

The workspace launcher script:

```bash
zj             # list active zellij sessions
zj kost        # attach to or create the kost workspace
```

- If a session named `<project>` exists → attach.
- Else if `~/code/<project>/zellij.kdl` exists → create with that layout.
- Else → create a bare session.

Strips ANSI codes from `zellij list-sessions` output before matching (defends against zellij's colored output breaking grep).

### `dot_local/bin/executable_wt`

The worktree + PR + merge wrapper. Used in place of raw `git worktree` / `gh pr` commands for the new-branch → review → merge lifecycle:

```bash
wt new <task>            # branch ../<repo>-<task> from origin/<default>
wt pr [gh-args…]         # rebase + force-push-with-lease + gh pr create
wt merge [strategy]      # merge PR (default --squash) + clean up worktree
wt rm <task> [--force]   # remove a worktree (refuses unless PR is MERGED)
wt help                  # full reference
```

`wt` is the deterministic core — four commands, human- and agent-usable, with safety gates baked in. The judgment layer lives in skills that compose these: list worktrees with `git worktree list`; clean up stale ones with the session-aware **`/prune`** skill (parks live sessions + checks for uncommitted work first); spawn a worktree-backed session with **`/new-work-session`**.

### `dot_local/bin/executable_devbox-scaffold`

Generates `./zellij.kdl` and `./.mise.toml` in a freshly-cloned repo, using the devbox's standard boilerplate (tab-bar + status-bar layout, always-on `shell` and `claude` tabs) plus per-project tabs passed as args:

```bash
devbox-scaffold api:api:dev mobile:mobile:dev worker
# → tabs: shell, claude, api (runs `mise run api:dev`),
#         mobile (runs `mise run mobile:dev`), worker (empty)
```

Invoked via the [`clone-repo`](../agents/skills/clone-repo/SKILL.md) skill — the skill inspects the repo first, proposes the right args, and waits for user confirmation before running.

### `dot_local/bin/executable_devbox-reprov`

Re-runs the devbox Ansible playbook locally on the VPS so reprovisioning doesn't require the laptop. Pulls the latest from `origin/main`, then `ansible-playbook -i ansible/inventory-local.ini ansible/site.yml "$@"`.

```bash
devbox-reprov                       # full reprov
devbox-reprov --tags docker         # just one role
devbox-reprov --check --diff        # dry-run preview
```

Needs Ansible installed locally (the `ansible-cli` role does this) and `~/code/devbox/` checked out (the `repos` role + `repos.txt`). First-time provision still has to come from the laptop.

### `dot_local/bin/executable_devbox-doctor`

Read-only health check for the VPS — mirrors the laptop-side `bin/doctor` but checks box-side state. Verifies:

- Expected binaries on PATH (mise, zellij, claude, cs, gh, rg, fd, jq, age, docker, chezmoi, tailscale, wt, zj, devbox-reprov, devbox-scaffold)
- Tailscale: daemon running, has tailnet IP, SSH enabled
- Docker daemon reachable as the current user
- `~/code/devbox/` is a clean git checkout, in sync with origin
- All agent-layer symlinks resolve (`~/.agents/`, `~/.claude/*`, `~/.codex/*`, including `~/.claude/settings.json`)
- Free memory + disk above thresholds

Exit code = number of failures (0 = healthy). Safe to wire into cron / CI as a smoke test.

```bash
devbox-doctor
```

### `dot_local/bin/executable_claude-sessions`

Read-only inventory of every **live Claude session** + git worktree on the box — facts only, no LLM. Process-driven (`pgrep -x claude`), so it catches a session even when its `~/.claude/sessions/<pid>.json` is missing; enriches each with sessionId / cwd / status / last-active from that json when present. For each worktree it shows the branch, which session(s) sit in it, and the uncommitted-file count.

```bash
claude-sessions
```

This is the shared engine under the `/sessions` skill (which adds a per-session gist from the transcript), the `/prune` skill, and the session-start ritual. Crucially it surfaces each session's `claude --resume <id>` line — the recovery path if a tab is closed.

### `dot_local/bin/executable_claude-spawn`

Opens a new Claude session in a fresh Zellij tab (`claude --remote-control <name>`, so it shows up named in the phone app). Codifies the new-tab + inline-layout dance.

```bash
claude-spawn --name <name> [--cwd <dir>] [--prompt-file <path>] [--resume <id>]
```

`--prompt-file` appends a file's contents to the system prompt (how `/new-work-session` primes its clarify→worktree→code protocol); `--resume` recovers an existing session by id. Backs the `/new-chat-session` and `/new-work-session` skills. Requires being inside a Zellij session.

### `dot_local/bin/executable_claude-park`

"Park, not kill" a session: records its `claude --resume <id>` line to `~/.claude/parked-sessions.log` **first**, then closes its Zellij tab. The close is reversible — the resume command is logged and the transcript persists on disk regardless.

```bash
claude-park <session-name>
```

Backs the `/prune` skill (which calls it under per-item confirmation). This is the deterministic "record-before-close" guarantee — the reason `/prune` can close a session without risk of losing it.

## Public API

- The destination paths (`~/.bashrc`, `~/.config/zellij/config.kdl`, `~/.local/bin/zj`, `~/.local/bin/wt`, `~/.local/bin/devbox-scaffold`, `~/.local/bin/devbox-reprov`, `~/.local/bin/devbox-doctor`) are the public surface.
- `zj` is the human/agent-facing way to attach to a project workspace.
- `wt` is the human/agent-facing way to drive the worktree → PR → merge lifecycle.
- `devbox-scaffold` is the human/agent-facing way to scaffold a new repo's dev contract (`.mise.toml` + `zellij.kdl`).
- `devbox-reprov` is the human/agent-facing way to re-run the playbook locally on the VPS.
- `devbox-doctor` is the read-only health check — runs in a few seconds, reports what's broken.
- `claude-sessions` is the read-only live-session + worktree inventory (shared engine under `/sessions`, `/prune`, and the session-start ritual).
- `claude-spawn` opens a new session in a Zellij tab (backs `/new-chat-session` + `/new-work-session`).
- `claude-park` records a session's resume id then closes its tab (backs `/prune`).

## How to extend

### Add a new dotfile

Pick the source path that produces the destination you want:

```
chezmoi/dot_vimrc                              → ~/.vimrc
chezmoi/dot_config/git/config                  → ~/.config/git/config
chezmoi/private_dot_aws/credentials            → ~/.aws/credentials (0600)
```

After editing, re-apply on the VPS:

```bash
chezmoi apply
# or, to re-run the role from the laptop:
ansible-playbook -i inventory.ini site.yml --tags dotfiles
```

### Add a per-machine variation

Rename the file to end in `.tmpl` and use Go template syntax referencing `chezmoi.data` or `.chezmoi.hostname`:

```
chezmoi/dot_bashrc.tmpl
```

```bash
{{- if eq .chezmoi.hostname "devbox" }}
export I_AM_THE_VPS=1
{{- end }}
```

### Add a secret

Use `encrypted_` prefix with `age`:

```bash
chezmoi encrypt < secret.txt > chezmoi/encrypted_private_dot_secret
```

Apply will decrypt at write time.

## How chezmoi is invoked

The Ansible `dotfiles` role does, as the `fum4` user:

```bash
chezmoi init --apply --source=<devbox-path>/chezmoi
```

That command:
1. Initializes chezmoi state at `~/.config/chezmoi/chezmoi.toml`
2. Pulls source from `<devbox-path>/chezmoi` (this directory)
3. Walks the tree, applies each file at its translated destination
4. Reports any conflicts

Subsequent applies (after editing this directory) can be run by the user on the VPS:

```bash
chezmoi apply
```

…or re-run the Ansible role from the laptop:

```bash
ansible-playbook -i ansible/inventory.ini ansible/site.yml --tags dotfiles
```

## Escape hatch: `~/.bashrc.local`

Anything truly machine-specific or experimental that you don't want to commit (one-off `export FOO=bar`, etc.) goes in `~/.bashrc.local` on the VPS. The chezmoi-managed `.bashrc` sources it if it exists. Promote stable additions back into this repo when ready.
