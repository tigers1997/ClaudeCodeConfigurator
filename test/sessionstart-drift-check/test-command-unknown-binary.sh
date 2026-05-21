#!/usr/bin/env bash
# A configured binary not in the manifest_for() universe (e.g., make) is
# skipped silently — same rule as stop-run-checks.sh.
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 2, "written_at": "2026-05-21T00:00:00Z",
  "written_by": "cc-configure 2.6.0",
  "mcp_servers": [],
  "stack_manifests": [],
  "check_commands": { "test": "make" } }
EOF
echo '{ "mcpServers": {} }' > "$tmp/.mcp.json"
# No Makefile, but make isn't in the universe → silent.

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
[ -z "$out" ] || { echo "FAIL: 'make' should be skipped; got: $out"; exit 1; }
echo "PASS: unknown binary (make) → silent"
