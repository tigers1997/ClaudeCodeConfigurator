#!/usr/bin/env bash
set -euo pipefail
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
echo "migrations/**" > "$TMPDIR/.claude/.guarded"
export CLAUDE_PROJECT_DIR="$TMPDIR"

# Match should reject
if echo '{"tool_name":"Edit","tool_input":{"file_path":"migrations/0042.sql"}}' \
   | bash templates/commands/microbit-enforcer/microbit-enforcer.sh 2>/dev/null; then
  echo "FAIL: should have rejected migrations/0042.sql"; exit 1
fi

# No match should pass
echo '{"tool_name":"Edit","tool_input":{"file_path":"src/api.py"}}' \
  | bash templates/commands/microbit-enforcer/microbit-enforcer.sh

echo "PASS: guarded glob blocks matches; passes non-matches"
