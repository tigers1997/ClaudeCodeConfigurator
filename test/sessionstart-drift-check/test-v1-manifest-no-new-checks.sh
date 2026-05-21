#!/usr/bin/env bash
# v1 manifest + new hook: MCP check still works, new dimensions skipped silently.
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 1, "written_at": "2026-05-13T00:00:00Z",
  "written_by": "cc-configure 2.5.0", "mcp_servers": ["git"] }
EOF
echo '{ "mcpServers": { "git": {"command":"echo"} } }' > "$tmp/.mcp.json"
# Stack files present at runtime — should NOT trigger drift on a v1 manifest.
touch "$tmp/package.json"

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: v1 manifest should be silent; got: $out"; exit 1; }
echo "PASS: v1 manifest skips new-dimension checks silently"
