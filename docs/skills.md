# Skills — custom + vendored

How agent skills (the on-demand `SKILL.md` capabilities Claude Code and Codex
load) are managed on the devbox. Two kinds, one delivery surface:

- **Custom skills** — hand-written, devbox-specific (`/sessions`, `/prune`,
  `/serve`, …). Live in [`../agents/skills/`](../agents/skills/), reviewed like
  any code.
- **Vendored skills** — third-party, from the open ecosystem
  ([skills.sh](https://skills.sh), GitHub). Managed by
  **[easyskills](https://github.com/fum4/easyskills)** (our own tool — this is
  its first production deployment): declared and **pinned to exact commits** in
  [`../easyskills/skills.toml`](../easyskills/skills.toml).

## Architecture

```
devbox repo (committed)                     live box (materialized)
─────────────────────────                   ──────────────────────────────
agents/skills/<name>/        ──ansible──▶   ~/.agents/skills/<name>      (symlink per custom skill)
easyskills/skills.toml       ──easyskills─▶ easyskills/.skills/<name>    (store, gitignored)
easyskills/skills.patches/      install        └─▶ ~/.agents/skills/<name> (symlink per vendored skill)

~/.claude/skills → ~/.agents/skills        (Claude Code user-level skills)
~/.codex/skills  → ~/.agents/skills        (Codex, same set)
```

- `~/.agents/skills` is a **real directory of per-skill symlinks** — one flat
  namespace; provenance is where each link points. The `agents` role creates
  the custom-skill links (and prunes dangling ones); `easyskills install`
  creates the vendored ones.
- The **easyskills home is inside this repo** (`$EASYSKILLS_HOME =
  ~/code/devbox/easyskills`, exported by chezmoi's `dot_bashrc`): the manifest
  with its commit pins is committed; the `.skills/` store and `.skills.pristine/`
  next to it are gitignored and rebuilt from the pins.
- **Roles**: `agents` (links custom skills) → `easyskills` (builds the binary
  from `~/code/easyskills` — cloned via `repos.txt` — and runs
  `easyskills --global install --locked`). A rebuilt box comes up with the
  exact same skills, byte-identical.

## Flows

| Goal | How |
|---|---|
| Add a vendored skill | `easyskills --global add github:<owner>/<repo> --include <skill>` → **read the fetched SKILL.md** (security pass, see below) → commit the `skills.toml` change |
| Check for upstream updates | `easyskills --global outdated` |
| Update (re-pin) | `easyskills --global update [source]` → review what changed (`easyskills diff`, upstream compare between pins) → commit the manifest change |
| Tweak a vendored skill locally | edit `easyskills/.skills/<name>/…` → `easyskills --global patch <name>` → commit `skills.patches/` (the patch re-applies through every update) |
| Remove | `easyskills --global remove <source-url>` → commit |
| Restore after rebuild | automatic (`easyskills` role); by hand: `easyskills --global install --locked` |
| Health check | `devbox-doctor` (binary on PATH, link integrity, offline `--locked` restore) |
| Add a custom skill | `mkdir agents/skills/<name>` + SKILL.md, commit; `devbox-reprov --tags agents` links it (or symlink by hand) |

`--include` filters match the skill's **frontmatter `name`**, not its directory
name (e.g. `vercel-react-best-practices`, not `react-best-practices`).

## Security policy

Vendored skills are **prompt-code running with `bypassPermissions`** — treat
every install/update as a supply-chain event:

1. **Read every file** of a newly added skill (SKILL.md + assets) before
   committing its pin. We security-review on first install.
2. **Review update diffs** the same way — `update` only moves pins; nothing
   changes silently because the manifest is committed.
3. **Installs require explicit user confirmation** — the vendored `find-skills`
   skill is patched (see `easyskills/skills.patches/`) to install via
   easyskills only, never `npx skills add -y`, and never unprompted.
4. Skills that ship data **off the box** (e.g. cloud-share skills like
   `agentspace`) are rejected by default — Remote Control already delivers
   artifacts to the phone.

## Currently vendored

See `easyskills --global list` (or read `easyskills/skills.toml`) — the
manifest is the truth, this doc deliberately doesn't duplicate the list.
First batch (2026-06-12) was security-reviewed file-by-file: 10 clean, 1
hardened by patch (`find-skills`, above).

## Known upstream quirks

- `anthropics/skills` is installed via the **subpath form**
  (`github:anthropics/skills/skills/frontend-design`) because the repo contains
  an unrelated skill whose `description` exceeds the spec's 1024-char limit and
  easyskills currently fails the whole source on any invalid skill — see
  easyskills `TODO.md` (validate only selected skills).
- `agent-browser` (wanted for ad-hoc browser verification) is **deferred**: its
  skill drives a binary we don't yet provision (no global node by design) —
  see `TODO.md`.
