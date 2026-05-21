#!/usr/bin/env bash
# Manifest baseline configured pnpm test; package.json is present. Hook silent.
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 2, "written_at": "2026-05-21T00:00:00Z",
  "written_by": "cc-configure 2.6.0",
  "mcp_servers": [],
  "stack_manifests": ["package.json"],
  "check_commands": { "test": "pnpm" } }
EOF
echo '{ "mcpServers": {} }' > "$tmp/.mcp.json"
touch "$tmp/package.json"

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: expected silent output; got: $out"; exit 1; }
echo "PASS: aligned commands → silent"
