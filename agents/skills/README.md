# skills/

On-demand capabilities for both Claude Code and Codex CLI, following the [Agent Skills open standard](https://agentskills.io). Each subdirectory is one skill with a `SKILL.md` entrypoint.

Skill files are deployed to `~/.agents/skills/` on the VPS by the `agents` Ansible role; both agents see them via the symlinks documented in [`../README.md`](../README.md).

## SKILL.md minimum

```markdown
---
name: skill-name
description: One sentence explaining when this skill should auto-trigger.
---

# Title

Instructions / reference content here.
```

The `description` is the most important field — it's what each agent uses to decide whether to auto-load the skill for the current task. Lead with the trigger phrasing the user is likely to use.

## Claude-specific frontmatter (Codex ignores)

| Field | Effect |
|---|---|
| `disable-model-invocation: true` | Only the user can invoke via `/skill-name`; agent never auto-loads. Good for actions with side effects. |
| `user-invocable: false` | Only the agent can invoke; hidden from `/` menu. Good for background reference. |
| `allowed-tools: Bash(git *) Read` | Pre-approve tools while skill is active. |
| `paths: "**/*.ts"` | Only auto-loads when working on files matching the glob. |
| `context: fork` | Run in a forked subagent (clean context). |

Codex equivalents live in `agents/openai.yaml` alongside `SKILL.md`. We're not using it yet.

## Currently shipped

| Skill | Triggers on |
|---|---|
| [`parallel-work`](parallel-work/) | Starting a new unrelated feature, parallel work, separate bug — guides the agent to use `wt new` for worktrees. |

## Adding a new skill — checklist

1. `mkdir -p agents/skills/<name>`
2. Write `agents/skills/<name>/SKILL.md`
3. Lead the `description` with the trigger phrasing
4. Keep the body concise (it stays in context once loaded)
5. Reference any wrapper commands (like `wt`) in the body — agent uses them, you don't reimplement
6. `ansible-playbook ... --tags agents` to deploy

## Sources

- [Agent Skills standard](https://agentskills.io)
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills)
- [Codex CLI Skills docs](https://developers.openai.com/codex/skills)
