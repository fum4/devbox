# devbox

Personal dev VPS provisioning + dotfiles. One repo, two layers:

- **`ansible/`** — provisions a Debian 12 VPS (Hetzner today; portable) into a fully configured dev box: hardened SSH, Tailscale, runtimes via mise, Claude Code, Zellij, agent tools.
- **`chezmoi/`** — user-level config (shell, zellij, mise globals, ssh) applied by the `dotfiles` Ansible role.

End state: from a freshly created VPS to a fully configured dev environment in one command:

```bash
ansible-playbook -i ansible/inventory.ini ansible/site.yml
```

## Status

🚧 Bootstrap in progress. See [`docs/plan.md`](docs/plan.md) for the full design + roadmap.

## How to use (once Phase 1 lands)

```bash
# 1. Provision a Hetzner CX33 via the UI (Debian 12, your SSH key)
# 2. Update inventory.ini with the new public IP
# 3. Run the playbook
ansible-playbook -i ansible/inventory.ini ansible/site.yml
# 4. SSH in: ssh vps; bring up a project workspace: zj <project>
```

Adding a new app: see [`docs/plan.md`](docs/plan.md) §Daily Workflow.
