#!/usr/bin/env bash
# Seed ~/.claude.json with a workspace-trust entry for ~/code so Claude Code
# sessions spawned anywhere underneath skip the trust dialog at startup.
#
# Why: spawned/headless sessions hit the trust dialog and block startup, never
# registering with Remote Control, so they never appear on the phone. Trust is
# parent-walking — one `true` entry at ~/code covers every repo + worktree
# under it.
#
# chezmoi semantics: `run_once_after_<...>.sh` runs once per machine after
# `chezmoi apply` finishes. The "once" is keyed by SHA256 of this file's
# contents, so editing the script (e.g. to add a second trust path) reruns it.
#
# Idempotent at runtime too — re-running on an already-trusted box is a no-op.
set -euo pipefail

CLAUDE_JSON="$HOME/.claude.json"
TRUST_PATH="$HOME/code"

[[ -f "$CLAUDE_JSON" ]] || echo '{}' > "$CLAUDE_JSON"

current=$(jq -r --arg p "$TRUST_PATH" \
    '.projects[$p].hasTrustDialogAccepted // false' "$CLAUDE_JSON" 2>/dev/null || echo "false")

if [[ "$current" == "true" ]]; then
    echo "claude-trust-bootstrap: $TRUST_PATH already trusted, skipping"
    exit 0
fi

tmp=$(mktemp)
jq --arg p "$TRUST_PATH" \
    '.projects[$p] = ((.projects[$p] // {}) + {hasTrustDialogAccepted: true})' \
    "$CLAUDE_JSON" > "$tmp" && mv "$tmp" "$CLAUDE_JSON"

echo "claude-trust-bootstrap: seeded $TRUST_PATH (hasTrustDialogAccepted=true)"
