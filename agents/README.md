# agents/

Everything agent-related: the always-loaded `AGENTS.md` and on-demand `skills/`. Both Claude Code and Codex CLI read from the same files via symlinks the playbook creates on the VPS.

## Layout

```
agents/
├── README.md           ← this file
├── AGENTS.md           ← user-level instructions, loaded into every session
└── skills/
    └── <skill-name>/
        ├── SKILL.md
        └── (optional: scripts/ references/ assets/)
```

## How it materializes on the VPS

The `agents` Ansible role creates `~/.agents/` as the cross-agent home (per the Agent Skills open standard), with each entry symlinked into this directory; both Claude Code's and Codex's expected paths then symlink at `~/.agents/`:

```
~/code/devbox/agents/                  ← canonical source (this directory, checked out on the VPS)
        ▲
        │ each entry below is a symlink into the source above
        │
~/.agents/                             ← agent-facing location (Agent Skills open standard)
├── AGENTS.md  →  ~/code/devbox/agents/AGENTS.md
├── README.md  →  ~/code/devbox/agents/README.md
└── skills     →  ~/code/devbox/agents/skills

~/.claude/CLAUDE.md  → ~/.agents/AGENTS.md
~/.claude/skills     → ~/.agents/skills
~/.codex/AGENTS.md   → ~/.agents/AGENTS.md
~/.codex/skills      → ~/.agents/skills
```

**One source of truth, live edits.** Editing a file under `~/code/devbox/agents/` *is* editing the deployed file — no copy step, no `chezmoi apply`, no ansible re-run. Both agents see the change on their next session.

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
| [`parallel-work`](skills/parallel-work/) | Starting a new unrelated feature, parallel work, separate bug — guides the agent to use `wt new` for worktrees. |

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

## Sources

- [Agent Skills standard](https://agentskills.io)
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills)
- [Codex CLI Skills docs](https://developers.openai.com/codex/skills)
- [Codex AGENTS.md docs](https://developers.openai.com/codex/guides/agents-md)
