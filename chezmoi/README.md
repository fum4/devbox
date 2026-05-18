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
| `encrypted_X` | `X` after decryption | Decrypted from age/gpg at apply time |
| `X.tmpl` | `X` after Go-template render | Per-machine variables substituted |
| `run_once_X.sh` | (runs once, never stored) | One-shot setup script |

Prefixes nest naturally: `private_dot_ssh/config` → `~/.ssh/config` with `0600` perms.

## What's here

```
chezmoi/
├── dot_bashrc                       → ~/.bashrc
├── dot_config/
│   └── zellij/
│       └── config.kdl               → ~/.config/zellij/config.kdl
└── dot_local/
    └── bin/
        └── executable_zj            → ~/.local/bin/zj   (chmod +x)
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

## Public API

- The destination paths (`~/.bashrc`, `~/.config/zellij/config.kdl`, `~/.local/bin/zj`) are the public surface.
- The `zj` command is intended to be the human-facing way to attach to a project workspace.

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
