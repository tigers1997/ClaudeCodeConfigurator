#!/usr/bin/env bash
# Verify enforcer passes through Write when no marker files exist.
set -euo pipefail
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
export CLAUDE_PROJECT_DIR="$TMPDIR"
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"}}' \
  | bash templates/commands/microbit-enforcer/microbit-enforcer.sh
echo "PASS: no markers → exit 0"
