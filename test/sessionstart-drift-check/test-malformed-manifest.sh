#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
echo "{ not valid json" > "$tmp/.claude/.cc-manifest.json"
echo '{ "mcpServers": {} }' > "$tmp/.mcp.json"

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: hook produced output on malformed manifest: '$out'"; exit 1; }
echo "PASS: malformed manifest → silent"
