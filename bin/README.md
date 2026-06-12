# bin/

Small utility scripts run from the **laptop** (not the VPS). Invoked directly: `./bin/<name>` from the repo root, or `<repo>/bin/<name>` from anywhere.

## What's here

| Script | Purpose |
|---|---|
| `doctor` | Verify the laptop is in a state where `ansible-playbook` will succeed. Read-only — reports what's missing, doesn't mutate anything. |
| `devbox-tf` | Terraform wrapper for `terraform/devbox/`: loads the R2 state creds (`.r2-backend.env`), cd's to the right dir, forwards all args to `terraform`. The one deliberate exception to "read-only by default" — `apply`/`destroy` mutate the VPS's existence ([`docs/terraform.md`](../docs/terraform.md)). |

## When to run `doctor`

- After each step in [`docs/laptop.md`](../docs/laptop.md) on a fresh laptop — green-lights you to proceed.
- Before running `ansible-playbook` for the first time on a new VPS — catches missing keys / unrestored `secrets.local` before they fail mid-provision.
- Anytime something feels broken (`ssh devbox` mysteriously fails, `git push` fails, etc.) — routes you to the doc section that fixes whatever's actually wrong.

```bash
./bin/doctor
```

Exit code is `0` if everything passes, the number of failures otherwise. Output is one line per check (✓ / ✗), with each failure followed by a one-line hint pointing at the doc section that fixes it.

## Conventions for this folder

- **Laptop-side only.** Anything that should run on the VPS belongs in `chezmoi/dot_local/bin/` (which becomes `~/.local/bin/` on the VPS via chezmoi).
- **Read-only by default.** Scripts here verify or report. Mutations to laptop state go through documentation; mutations to VPS state go through Ansible.
- **No new dependencies.** Stick to bash + what [`docs/laptop.md`](../docs/laptop.md) §2 already requires on PATH (brew, age, ansible, gh, git, ssh-keygen).
- **No extension on filenames.** Matches the chezmoi-managed scripts (`zj`, `wt`, `devbox-scaffold`).
- **Read `devbox_user`** from `ansible/group_vars/all.yml` rather than hardcoding it. One source of truth across the whole repo.
