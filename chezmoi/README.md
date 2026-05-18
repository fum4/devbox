# chezmoi source

Dotfile sources applied to `$HOME` by chezmoi (invoked from the `dotfiles` Ansible role).

## Naming conventions (chezmoi attributes)

| Source path | Becomes | Why |
|---|---|---|
| `dot_X` | `.X` | The `dot_` prefix is replaced with a literal `.` |
| `executable_X` | `X` with `+x` | Adds the executable permission |
| `private_X` | `X` with `0600` / `0700` | Owner-only permissions |
| `X.tmpl` | `X` after template render | Go-template syntax |

So `dot_local/bin/executable_zj` becomes `~/.local/bin/zj` (executable).

## Layout

```
dot_bashrc                      → ~/.bashrc
dot_config/zellij/config.kdl    → ~/.config/zellij/config.kdl
dot_local/bin/executable_zj     → ~/.local/bin/zj   (+x)
```

## How it's applied

The `dotfiles` Ansible role does, as the `fum4` user:

```bash
chezmoi init --apply --source=<devbox>/chezmoi
```

After that, just `chezmoi apply` (chezmoi remembers the source dir).

## Local overrides

Anything machine-specific can go in `~/.bashrc.local` — the chezmoi-managed `.bashrc` sources it if present. Keep ephemeral / experimental config there; promote to this repo when stable.
