#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 1, "written_at": "2026-05-13T00:00:00Z",
  "written_by": "cc-configure 2.5.0", "mcp_servers": ["git"] }
EOF
echo "{ not valid json" > "$tmp/.mcp.json"

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: hook produced output on malformed .mcp.json: '$out'"; exit 1; }
echo "PASS: malformed .mcp.json → silent"
