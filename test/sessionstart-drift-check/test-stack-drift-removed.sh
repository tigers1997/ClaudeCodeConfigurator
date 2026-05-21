#!/usr/bin/env bash
# v2 manifest baseline had package.json. Repo no longer has it.
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 2, "written_at": "2026-05-21T00:00:00Z",
  "written_by": "cc-configure 2.6.0",
  "mcp_servers": [],
  "stack_manifests": ["package.json"],
  "check_commands": {} }
EOF
echo '{ "mcpServers": {} }' > "$tmp/.mcp.json"
# (no package.json created → it counts as removed)

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
echo "$out" | grep -q "stack drift" \
    || { echo "FAIL: missing 'stack drift': '$out'"; exit 1; }
echo "$out" | grep -q "removed package.json" \
    || { echo "FAIL: missing 'removed package.json': '$out'"; exit 1; }
echo "PASS: stack drift — removed package.json reported"
