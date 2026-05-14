#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 1, "written_at": "2026-05-13T00:00:00Z",
  "written_by": "cc-configure 2.5.0", "mcp_servers": ["a", "b"] }
EOF
cat > "$tmp/.mcp.json" <<'EOF'
{ "mcpServers": { "b": {"command":"echo"}, "c": {"command":"echo"}, "d": {"command":"echo"} } }
EOF

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
echo "$out" | grep -q "2 added (c, d)" \
    || { echo "FAIL: expected '2 added (c, d)', got: $out"; exit 1; }
echo "$out" | grep -q "1 removed (a)" \
    || { echo "FAIL: expected '1 removed (a)', got: $out"; exit 1; }
echo "$out" | grep -q " / " \
    || { echo "FAIL: missing ' / ' separator between add and remove segments, got: $out"; exit 1; }
echo "PASS: mixed adds + removes → combined summary"
