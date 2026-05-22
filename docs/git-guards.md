# Git guards

A devbox-wide **pre-push hook** that refuses two easy-to-do-by-accident
mistakes against protected branches (`master`, `main`):

- **deleting** the branch (`git push origin --delete master`)
- **force-pushing** / rewriting history (non-fast-forward push)

This is an *accidental-safety net*, not a security control — it's bypassable
with `git push --no-verify` for the rare time you genuinely mean it.

## Why a local hook (not GitHub branch protection)

GitHub branch-protection rules and rulesets require a paid plan for **private**
repos (or making the repo public). The repos here are private on the free tier,
so server-side protection isn't available. A local `pre-push` hook is the
pragmatic equivalent for catching accidents.

> Note: GitHub *already* refuses to delete a repo's **default** branch via the
> UI/API regardless of plan — so `master` can't be deleted remotely anyway.
> This hook adds force-push protection and covers `main` too, locally, before
> anything leaves the machine.

## How it's wired (chezmoi)

Managed entirely in `chezmoi/`, so it survives a rebuild:

| File | Applied to | Purpose |
|---|---|---|
| `chezmoi/dot_config/git/config` | `~/.config/git/config` | sets `core.hooksPath = ~/.config/git/hooks` (global, XDG scope — kept separate from `~/.gitconfig` identity) |
| `chezmoi/dot_config/git/hooks/executable_pre-push` | `~/.config/git/hooks/pre-push` | the guard script |

`core.hooksPath` makes **every** repo on the box use this hooks directory, so
the guard is global. A repo that needs its own hooks (e.g. husky) sets a
repo-local `core.hooksPath`, which overrides the global one.

Applied on provision by the `dotfiles` role (`chezmoi apply`). To apply by hand
after editing: `chezmoi apply ~/.config/git`.

## Changing the protected set

Edit the `protected_regex` in the hook. Re-apply with `chezmoi apply ~/.config/git`.

## Verifying

```
# should print the refusal and exit non-zero
git push --dry-run origin --delete master
```
