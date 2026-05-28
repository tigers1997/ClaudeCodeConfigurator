#!/usr/bin/env bash
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

input='{"tool_name":"Bash","tool_input":{"command":"apt install postgresql-*"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc for glob (expected 0)"; exit 1; }
echo "$out" | grep -q "glob in pkg name" || { echo "FAIL: missing glob bail note"; exit 1; }
echo "PASS: glob bails"
