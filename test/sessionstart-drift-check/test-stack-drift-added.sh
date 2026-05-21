#!/usr/bin/env bash
# v2 manifest baseline: package.json only. Repo now also has pyproject.toml.
# Hook emits a stack-drift line naming the new manifest.
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
touch "$tmp/package.json" "$tmp/pyproject.toml"

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
echo "$out" | grep -q "stack drift" \
    || { echo "FAIL: missing 'stack drift' in output: '$out'"; exit 1; }
echo "$out" | grep -q "added pyproject.toml" \
    || { echo "FAIL: missing 'added pyproject.toml': '$out'"; exit 1; }
echo "$out" | grep -q "/verify-setup" \
    || { echo "FAIL: missing /verify-setup pointer: '$out'"; exit 1; }
echo "PASS: stack drift — added pyproject.toml reported"
