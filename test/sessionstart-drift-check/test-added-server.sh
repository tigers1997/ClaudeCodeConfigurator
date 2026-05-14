#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 1, "written_at": "2026-05-13T00:00:00Z",
  "written_by": "cc-configure 2.5.0", "mcp_servers": ["git"] }
EOF
cat > "$tmp/.mcp.json" <<'EOF'
{ "mcpServers": { "git": {"command":"echo"}, "shadcn": {"command":"npx","args":["shadcn@latest"]} } }
EOF

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
echo "$out" | grep -q "1 added (shadcn)" \
    || { echo "FAIL: expected '1 added (shadcn)' in output, got: $out"; exit 1; }
echo "$out" | grep -q "Run /verify-setup for tradeoffs" \
    || { echo "FAIL: missing /verify-setup pointer in output: $out"; exit 1; }
echo "PASS: one added server → expected one-line summary"
