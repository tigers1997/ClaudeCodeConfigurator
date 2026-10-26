#!/usr/bin/env bash
# /guard must BLOCK matching paths with exit code 2 — the only non-zero code
# Claude Code treats as a block (exit 1 is a non-blocking error and the edit
# lands) — and let everything else through with exit 0.
set -euo pipefail
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
echo "migrations/**" > "$TMPDIR/.claude/.guarded"
export CLAUDE_PROJECT_DIR="$TMPDIR"

# Match must reject with exit 2 exactly.
set +e
echo '{"tool_name":"Edit","tool_input":{"file_path":"migrations/0042.sql"}}' \
   | bash templates/commands/microbit-enforcer/microbit-enforcer.sh 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: guarded match must exit 2; got $rc"; exit 1; }

# No match should pass
echo '{"tool_name":"Edit","tool_input":{"file_path":"src/api.py"}}' \
  | bash templates/commands/microbit-enforcer/microbit-enforcer.sh

echo "PASS: guarded glob blocks matches with exit 2; passes non-matches"
