#!/usr/bin/env bash
# Manifest version > 1 → hook emits one-line "version mismatch" notice and exits 0.
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 2, "written_at": "2026-05-13T00:00:00Z",
  "written_by": "cc-configure 3.0.0", "mcp_servers": ["git"] }
EOF
echo '{ "mcpServers": {} }' > "$tmp/.mcp.json"

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
echo "$out" | grep -q "manifest version 2" \
    || { echo "FAIL: missing version note in output: '$out'"; exit 1; }
echo "$out" | grep -q "this hook is v1" \
    || { echo "FAIL: missing 'hook is v1' phrasing: '$out'"; exit 1; }
echo "$out" | grep -q "please update cc-configure" \
    || { echo "FAIL: missing upgrade recommendation: '$out'"; exit 1; }
echo "PASS: future manifest version emits one-line upgrade notice"
