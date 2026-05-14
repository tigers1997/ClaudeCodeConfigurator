#!/usr/bin/env bash
# No manifest → hook exits 0 silently.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# No .claude/ at all
out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: hook produced output with no manifest: '$out'"; exit 1; }

# Empty .claude/ also fine
mkdir -p "$tmp/.claude"
out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: hook produced output with empty .claude/: '$out'"; exit 1; }

echo "PASS: no manifest → silent"
