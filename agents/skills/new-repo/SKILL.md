---
name: new-repo
description: Create a brand-new GitHub repo under fum4/, clone it locally, scaffold the devbox dev contract (`.mise.toml` + `zellij.kdl`), wire it into `devbox/repos.txt` so rebuilds reclone it, and spawn a Claude session in it. Trigger on "/new-repo", "create a new repo", "scaffold a new project", "make a new GitHub repo for X", "start a new repo and a session in it". Use this when the repo does NOT yet exist on GitHub; use `/clone-repo` when it already does.
---

# /new-repo — create + scaffold + spawn

End state: `fum4/<name>` exists on GitHub, is cloned to `~/code/<name>` with a scaffolded dev contract committed and pushed, is tracked in `~/code/devbox/repos.txt` so rebuilds reclone it, and a fresh Claude session is running in it — driveable from the phone.

Use `/clone-repo` if the repo already exists on GitHub.

> **No trust step needed.** Claude Code's trust check walks parent directories — `$HOME` is already trusted in `~/.claude.json`, so anything under `~/code/` inherits. Spawned sessions in fresh `~/code/<name>` paths register with Remote Control directly.

## Steps

1. **Gather inputs** with one `AskUserQuestion` call (don't drip):
   - **name** — short kebab-case; also becomes the Zellij tab + Claude session name. Per AGENTS.md, never auto-counter (`project-1`); insist on something meaningful.
   - **description** — one line, becomes the GitHub repo description.
   - **visibility** — `private` (default) or `public`.
   - **scaffold tabs** — args for `devbox-scaffold` (e.g. `api:api:dev mobile:mobile:dev worker`, or `none` to skip). See `devbox-scaffold --help` for the `<tab>[:<task>]` syntax.

2. **Pre-flight** — fail fast and surface clearly if either is dirty:
   ```bash
   gh repo view fum4/<name>          # expected: non-zero exit, "not found"
   test -e ~/code/<name>             # expected: non-zero, path doesn't exist
   ```
   If either tripped, stop and ask — don't auto-recover, drift needs a human call.

3. **Create on GitHub + clone locally**:
   ```bash
   cd ~/code
   gh repo create fum4/<name> --<vis> --description "<desc>" \
      --clone --add-readme --license mit --gitignore <template>
   ```
   Pick `--gitignore` to fit the scaffold (`Node` for JS/TS, `Python` for py, `Go`, `Rust` …); when unsure, default `Node`.

4. **Scaffold the dev contract** (skip if user picked `none`):
   ```bash
   cd ~/code/<name> && devbox-scaffold <tab-args>
   ```
   Produces `.mise.toml` + `zellij.kdl`. Only fills gaps — won't overwrite existing files unless `--force`.

5. **First commit + push** (only if step 4 added files):
   ```bash
   cd ~/code/<name>
   git add .mise.toml zellij.kdl <anything else scaffold dropped>
   git commit -m "chore(scaffold): devbox dev contract"
   git push
   ```

6. **Wire into `~/code/devbox/repos.txt`** so a rebuild reclones it:
   - Append `fum4/<name>` (keep alphabetical if existing lines are).
   - Commit + push in the devbox repo: `chore(repos): track fum4/<name>`.

7. **Spawn the session**:
   ```bash
   claude-spawn --name <name> --cwd ~/code/<name>
   ```

8. **Report back**: GitHub URL (`gh repo view fum4/<name> --json url -q .url`), local path, reminder to refresh the phone Claude app — it'll appear in ~10s.

## Rules

- **Always `--private` by default.** `gh repo create` on a personal account creates public if you don't pass a visibility flag; almost everything here should be private.
- **Never `gh repo create` without `--description`.** Empty descriptions are a smell on personal repos; ask if the user didn't supply one.
- **Never auto-name with a counter** (`project-1`, `app-2`). The name doubles as session + tab name; demand something meaningful. AGENTS.md rule.
- **Don't skip step 6 (repos.txt).** A repo not listed survives on GitHub but vanishes on the next devbox rebuild — silent drift.
- **Don't auto-recover from pre-flight failures.** Existing `~/code/<name>` or existing `fum4/<name>` mean something the user needs to decide about — stop and ask.
