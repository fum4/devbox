# ansible/secrets/

Age-encrypted secrets consumed by the Ansible playbook. The encryption pattern, threat model, restore procedure, and recipes for adding new secrets are documented in [`../../docs/secrets.md`](../../docs/secrets.md) — read that first.

## What's here

| File | Plaintext | Consumed by |
|---|---|---|
| `github-fum4.age` | OpenSSH ed25519 private key | `github-identity` role |
| `github-pat.age` | GitHub PAT (`ghp_…`) | `github-identity` role |
| `tailscale-oauth.age` | Tailscale OAuth `client_secret` | `tailscale` role |

All three encrypted to the public key at the top of `~/_work/devbox/secrets.local` (gitignored, backed up to password manager).

## Gitignore policy

The repo `.gitignore` enforces:

```
ansible/secrets/*        ← everything ignored by default
!ansible/secrets/.gitkeep
!ansible/secrets/*.age   ← except .age files (these commit)
```

So plaintext drops (`*.txt`, `*.pem`, etc.) never accidentally commit. Encrypted blobs are explicit opt-in via the `.age` extension.

## Don't

- Don't `git add` plaintext files in this folder. The gitignore catches most extensions, but `git add -f` would override it.
- Don't decrypt to a file in this folder ever — `> secrets/foo.txt` lands one stray `git add -A` away from disaster. Decrypt to `/tmp/` and `shred -u` after.
- Don't add `.age` files encrypted to a different age recipient than `secrets.local` holds. They'll be undecryptable on this machine and fail Ansible runs silently.
