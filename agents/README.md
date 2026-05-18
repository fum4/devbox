# agents/

Everything agent-related: the always-loaded `AGENTS.md` and on-demand `skills/`. Both Claude Code and Codex CLI read from the same files via symlinks the playbook creates on the VPS.

## Layout

```
agents/
├── README.md           ← this file
├── AGENTS.md           ← user-level instructions, loaded into every session
└── skills/
    ├── README.md
    └── <skill-name>/
        ├── SKILL.md
        └── (optional: scripts/ references/ assets/)
```

## How it materializes on the VPS

The `agents` Ansible role rsyncs this directory to `~/.agents/` on the VPS, then symlinks each agent's expected paths at it:

```
~/.agents/                          ← canonical (open-standard location)
├── AGENTS.md
└── skills/

~/.claude/CLAUDE.md  → ~/.agents/AGENTS.md
~/.claude/skills     → ~/.agents/skills
~/.codex/AGENTS.md   → ~/.agents/AGENTS.md
~/.codex/skills      → ~/.agents/skills          (Codex actually reads ~/.agents/skills natively;
                                                  this symlink is for consistency)
```

**One source of truth.** Edit a file under `agents/` on your laptop, run the `agents` Ansible role (or `--tags agents`), both agents on the VPS see the change.

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

## Adding a new skill

1. `mkdir -p agents/skills/<name>`
2. Create `agents/skills/<name>/SKILL.md` with frontmatter (`name`, `description`) + markdown body
3. Optionally add `scripts/`, `references/`, or `assets/` subdirs
4. Re-run the playbook: `ansible-playbook -i ansible/inventory.ini ansible/site.yml --tags agents`
5. Both Claude and Codex will pick it up on their next session

## Editing AGENTS.md

1. Edit `agents/AGENTS.md`
2. Re-deploy: `ansible-playbook ... --tags agents`
3. Open a fresh session on either agent — new content is loaded

## Sources

- [Agent Skills standard](https://agentskills.io)
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills)
- [Codex CLI Skills docs](https://developers.openai.com/codex/skills)
- [Codex AGENTS.md docs](https://developers.openai.com/codex/guides/agents-md)
