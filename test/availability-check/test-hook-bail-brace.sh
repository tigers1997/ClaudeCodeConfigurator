#!/usr/bin/env bash
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

input='{"tool_name":"Bash","tool_input":{"command":"apt install pkg-{a,b}"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc for brace (expected 0)"; exit 1; }
echo "$out" | grep -q "brace expansion" || { echo "FAIL: missing brace bail note"; exit 1; }
echo "PASS: brace expansion bails"
