#!/usr/bin/env bash
# Manifest matches current .mcp.json → silent.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 1, "written_at": "2026-05-13T00:00:00Z",
  "written_by": "cc-configure 2.5.0", "mcp_servers": ["context7", "git"] }
EOF
cat > "$tmp/.mcp.json" <<'EOF'
{ "mcpServers": { "context7": {"command":"echo"}, "git": {"command":"echo"} } }
EOF

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: hook output on no-drift: '$out'"; exit 1; }
echo "PASS: matching manifest + .mcp.json → silent"
