#!/usr/bin/env bash
# // comment keys in .mcp.json must not appear in drift output.
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 1, "written_at": "2026-05-13T00:00:00Z",
  "written_by": "cc-configure 2.5.0", "mcp_servers": ["git"] }
EOF
cat > "$tmp/.mcp.json" <<'EOF'
{ "mcpServers": {
    "//note": "this is a doc key",
    "git": {"command":"echo"}
} }
EOF

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: hook reported drift on // comment-only diff: '$out'"; exit 1; }
echo "PASS: // comment keys ignored when diffing"
