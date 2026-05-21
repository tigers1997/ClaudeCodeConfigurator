#!/usr/bin/env bash
# Manifest baseline configured pnpm tooling; repo has no package.json now.
# Hook emits a command-misalignment line covering both Node-family configs.
# Note: only package-manager binaries (pnpm/npm/uv/cargo/...) are in the
# manifest_for() table — direct tools like tsc/pytest/ruff/eslint are
# unguarded (consistent with stop-run-checks.sh's skip rules).
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

mkdir -p "$tmp/.claude"
cat > "$tmp/.claude/.cc-manifest.json" <<'EOF'
{ "manifest_version": 2, "written_at": "2026-05-21T00:00:00Z",
  "written_by": "cc-configure 2.6.0",
  "mcp_servers": [],
  "stack_manifests": [],
  "check_commands": { "lint": "pnpm", "test": "pnpm" } }
EOF
echo '{ "mcpServers": {} }' > "$tmp/.mcp.json"
# No package.json — both pnpm-prefixed configs need it.

out=$(CLAUDE_PROJECT_DIR="$tmp" bash templates/mcp/hooks/sessionstart-drift-check.sh 2>&1)
echo "$out" | grep -q "command misalignment" \
    || { echo "FAIL: missing 'command misalignment': '$out'"; exit 1; }
echo "$out" | grep -q "lint (pnpm needs package.json)" \
    || { echo "FAIL: missing lint mismatch: '$out'"; exit 1; }
echo "$out" | grep -q "test (pnpm needs package.json)" \
    || { echo "FAIL: missing test mismatch: '$out'"; exit 1; }
echo "PASS: command misalignment — both pnpm-configured tools flagged"
