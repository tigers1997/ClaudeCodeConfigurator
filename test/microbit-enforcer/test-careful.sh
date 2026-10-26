#!/usr/bin/env bash
# /careful must produce the documented PreToolUse decision JSON
# (hookSpecificOutput.permissionDecision = "ask") on exit 0. The hook used to
# print {"action": "ask", ...}, a shape Claude Code documents only for
# Elicitation hooks, so no prompt ever appeared.
set -euo pipefail
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
echo "auth/**" > "$TMPDIR/.claude/.careful"
export CLAUDE_PROJECT_DIR="$TMPDIR"
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"auth/login.py"}}' \
      | bash templates/commands/microbit-enforcer/microbit-enforcer.sh)
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
h = d["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse", h
assert h["permissionDecision"] == "ask", h
assert "auth/login.py" in h["permissionDecisionReason"], h
assert "auth/**" in h["permissionDecisionReason"], h
' || { echo "FAIL: expected a PreToolUse permissionDecision=ask object; got: $out"; exit 1; }

# A path with a quote must still produce valid JSON (json.dumps escapes it).
echo "notes/**" >> "$TMPDIR/.claude/.careful"
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"notes/it'"'"'s \"here\".md"}}' \
      | bash templates/commands/microbit-enforcer/microbit-enforcer.sh)
printf '%s' "$out" | python3 -c 'import json, sys; json.load(sys.stdin)' \
    || { echo "FAIL: quote in path produced malformed JSON: $out"; exit 1; }

echo "PASS: careful glob emits a PreToolUse ask decision"
