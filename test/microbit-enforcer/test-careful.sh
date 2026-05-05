#!/usr/bin/env bash
set -euo pipefail
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
echo "auth/**" > "$TMPDIR/.claude/.careful"
export CLAUDE_PROJECT_DIR="$TMPDIR"
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"auth/login.py"}}' \
      | bash templates/commands/microbit-enforcer/microbit-enforcer.sh)
echo "$out" | grep -q '"action": "ask"' || { echo "FAIL: expected ask action; got: $out"; exit 1; }
echo "PASS: careful glob emits ask action"
