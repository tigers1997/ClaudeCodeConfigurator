#!/usr/bin/env bash
# /freeze must BLOCK, and Claude Code's hooks contract says only exit code 2
# blocks a PreToolUse call: exit 1 is a "non-blocking error" (the message
# shows, the edit lands). The hook used to exit 1, so this test pins the exact
# code rather than "any non-zero".
set -euo pipefail
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
touch "$TMPDIR/.claude/.frozen"
export CLAUDE_PROJECT_DIR="$TMPDIR"
set +e
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"}}' \
   | bash templates/commands/microbit-enforcer/microbit-enforcer.sh 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: frozen must exit 2 (the only exit code Claude Code treats as a block); got $rc"; exit 1; }
echo "PASS: frozen → exit 2"
