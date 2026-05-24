#!/usr/bin/env bash
# Hook must also suppress when superpowers is installed from an alternative
# marketplace (e.g., obra/superpowers-marketplace), not just claude-plugins-official.
# The hook uses a glob over ~/.claude/plugins/cache/*/superpowers.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Simulate plugin installed from a NON-official marketplace
mkdir -p "$tmp/.claude/plugins/cache/obra-superpowers-marketplace/superpowers/5.1.0"

out=$(HOME="$tmp" CLAUDE_PROJECT_DIR="$tmp" bash templates/discipline-skills/hooks/sessionstart-discipline.sh 2>&1)

[ -z "$out" ] || { echo "FAIL: hook produced output when plugin from alt marketplace installed: $out"; exit 1; }

echo "PASS: hook silent when superpowers is installed from a non-official marketplace"
