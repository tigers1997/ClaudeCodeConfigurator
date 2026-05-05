#!/usr/bin/env bash
set -euo pipefail
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
touch "$TMPDIR/.claude/.frozen"
export CLAUDE_PROJECT_DIR="$TMPDIR"
if echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"}}' \
   | bash templates/commands/microbit-enforcer/microbit-enforcer.sh 2>/dev/null; then
  echo "FAIL: should have rejected when frozen"; exit 1
fi
echo "PASS: frozen → exit non-zero"
