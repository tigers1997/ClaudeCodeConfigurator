#!/usr/bin/env bash
# All three drift dimensions simultaneously → all three lines emitted.
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 2, "written_at": "2026-05-21T00:00:00Z",
  "written_by": "cc-configure 2.6.0",
  "mcp_servers": ["git"],
  "stack_manifests": ["package.json"],
  "check_commands": { "test": "pnpm" } }
EOF
# MCP: git removed, new shadcn added.
cat > "$tmp/.mcp.json" <<'EOF'
{ "mcpServers": { "shadcn": {"command":"npx","args":["shadcn@latest"]} } }
EOF
# Stack: package.json removed, pyproject.toml added.
touch "$tmp/pyproject.toml"
# Command: pnpm still configured, but package.json is gone.

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)

echo "$out" | grep -q "MCP drift" \
    || { echo "FAIL: missing MCP drift line: $out"; exit 1; }
echo "$out" | grep -q "stack drift" \
    || { echo "FAIL: missing stack drift line: $out"; exit 1; }
echo "$out" | grep -q "command misalignment" \
    || { echo "FAIL: missing command misalignment line: $out"; exit 1; }

# Expect exactly three drift lines (one per dimension)
lines=$(echo "$out" | grep -c "cc-configure:")
[ "$lines" = "3" ] || { echo "FAIL: expected 3 cc-configure: lines, got $lines: $out"; exit 1; }

echo "PASS: all three drift dimensions emit simultaneously"
