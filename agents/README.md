# agents/

Everything agent-related: the always-loaded `AGENTS.md`, on-demand `skills/`, and per-agent runtime config (currently `claude/`). All of it is **symlinked** into the user's home on the VPS so edits in this directory are live the moment you save.

## Layout

```
agents/
├── README.md           ← this file
├── AGENTS.md           ← user-level instructions, loaded into every session
├── claude/             ← Claude Code runtime config
│   └── settings.json     theme, permissions defaults, push-notif prefs, etc.
└── skills/             ← on-demand capabilities (Agent Skills standard)
    └── <skill-name>/
        ├── SKILL.md
        └── (optional: scripts/ references/ assets/)
```

## How it materializes on the VPS

The `agents` Ansible role creates `~/.agents/` as the cross-agent home (per the Agent Skills open standard), with each entry symlinked into this directory; both Claude Code's and Codex's expected paths then symlink at `~/.agents/`. A separate chezmoi `symlink_` stub (`chezmoi/dot_claude/symlink_settings.json`) points `~/.claude/settings.json` straight at `agents/claude/settings.json`:

```
~/code/devbox/agents/                  ← canonical source (this directory, checked out on the VPS)
        ▲
        │ each entry below is a symlink into the source above
        │
~/.agents/                             ← agent-facing location (Agent Skills open standard)
├── AGENTS.md  →  ~/code/devbox/agents/AGENTS.md
├── README.md  →  ~/code/devbox/agents/README.md
└── skills     →  ~/code/devbox/agents/skills

~/.claude/CLAUDE.md          → ~/.agents/AGENTS.md
~/.claude/skills             → ~/.agents/skills
~/.claude/settings.json      → ~/code/devbox/agents/claude/settings.json   (via chezmoi)
~/.codex/AGENTS.md           → ~/.agents/AGENTS.md
~/.codex/skills              → ~/.agents/skills
```

**One source of truth, live edits.** Editing a file under `~/code/devbox/agents/` *is* editing the deployed file — no copy step, no `chezmoi apply`, no ansible re-run for content changes. Both agents see the change on their next session. `chezmoi apply` or the ansible role only need to run once, when *introducing* a new symlinked path under here.

## AGENTS.md vs skills — when to use which

**`AGENTS.md`** is loaded into every session for every project, so its content is a recurring token cost. Reserve it for:

- Environment description (what tools are available, where projects live)
- Cross-project conventions (workflow rules, things to never do)
- Tool wrapper announcements (e.g., "use `wt` not raw git worktree")

Keep it concise — every line costs context on every session.

**`skills/<name>/SKILL.md`** loads on demand when the agent decides the skill's `description` matches the current task. Reserve them for:

- Deep procedures (multi-step workflows worth codifying)
- Decision trees ("when to use X vs Y")
- Knowledge that doesn't apply to every session but matters when it does

A skill's body stays in context for the rest of the session once loaded. State what to do, not why.

## SKILL.md format

Each skill is a directory under `skills/` containing a `SKILL.md` file with frontmatter:

```markdown
---
name: skill-name
description: One sentence explaining when this skill should auto-trigger.
---

# Title

Instructions / reference content here.
```

The `description` is the most important field — both agents use it to decide whether to auto-load the skill for the current task. Lead with the trigger phrasing the user is likely to use.

## Currently shipped

| Skill | Triggers on |
|---|---|
| [`sessions`](skills/sessions/) | `/sessions`, `/status`, or "what's running" — full inventory: every Claude session (one-line gist from the *transcript*, not the name), every worktree (uncommitted / no-session flags), and the dev-server stacks. Backs the session-start ritual. Built on the `claude-sessions` helper. |
| [`help`](skills/help/) | `/help` — list all available skills + one-line descriptions. |
| [`prune`](skills/prune/) | `/prune` — clean-up review board: every session + worktree with WIP facts (`wt wip`) and a suggested action each (keep / park / kill / remove); the user picks, per item. Nothing acts without confirmation. |
| [`park`](skills/park/) | `/park` — stop a session, keep the conversation + worktree. Surfaces WIP first; reversible with `claude-restore`. |
| [`kill`](skills/kill/) | `/kill` — destroy a session + its worktree, deliberately. Surfaces what's lost, requires explicit acknowledgment; never removes a main checkout. |
| [`new-chat-session`](skills/new-chat-session/) | `/new-chat-session` — spawn a fresh general-purpose session (via `claude-spawn`), attachable from the phone. |
| [`new-work-session`](skills/new-work-session/) | `/new-work-session` — spawn a session primed (via `--append-system-prompt`) to clarify the task, then create a worktree before writing any code. |
| [`new-repo`](skills/new-repo/) | `/new-repo` — create a brand-new GitHub repo under fum4/, scaffold the dev contract, wire into `repos.txt`, spawn a session. |
| [`clone-repo`](skills/clone-repo/) | Cloning / setting up / starting work on an existing GitHub repo on the devbox — clone, inspect, propose `devbox-scaffold`, wait for approval, scaffold, open workspace. |
| [`serve`](skills/serve/) | `/serve` — start / stop / restart / check the dev servers for the current repo/worktree. Inspects what's bound, identifies which worktree owns each process, asks before killing competing servers. |

When to use a worktree is a judgment call, not a skill — see `AGENTS.md` → "When to use a worktree" (quick fix → default branch; feature-sized → propose a worktree first).

## Adding a new skill

1. `mkdir -p agents/skills/<name>`
2. Write `agents/skills/<name>/SKILL.md` with frontmatter (`name`, `description`) + markdown body
3. Lead the `description` with the trigger phrasing the user is likely to use
4. Optionally add `scripts/`, `references/`, or `assets/` subdirs
5. Commit + push — both agents pick it up on their next session (the symlink chain points here directly, no re-deploy needed)

## Editing AGENTS.md

1. Edit `agents/AGENTS.md`
2. Commit + push
3. Open a fresh session on either agent — new content is loaded

No re-deploy step: `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` resolve through `~/.agents/AGENTS.md` straight to this file.

## Editing Claude Code config

`agents/claude/settings.json` is the source for `~/.claude/settings.json` (theme, permissions defaults, push-notif prefs, etc. — see the [settings.json schema](https://docs.claude.com/en/docs/claude-code/settings)).

1. Edit `agents/claude/settings.json`
2. Commit + push
3. Open a fresh Claude Code session — new settings are loaded

No `chezmoi apply` needed for content changes — `~/.claude/settings.json` is a symlink into this file. Only re-run `chezmoi apply` if you're adding a *new* file under `agents/claude/` (so chezmoi can create the corresponding symlink at `~/.claude/<name>`).

## Sources

- [Agent Skills standard](https://agentskills.io)
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills)
- [Codex CLI Skills docs](https://developers.openai.com/codex/skills)
- [Codex AGENTS.md docs](https://developers.openai.com/codex/guides/agents-md)
