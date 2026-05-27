#!/usr/bin/env bash
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

# Note: $(...) is caught by composite check; this tests plain $VAR which slips through composite.
input='{"tool_name":"Bash","tool_input":{"command":"apt install $PKG"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc for var (expected 0)"; exit 1; }
echo "$out" | grep -q "shell var in pkg name" || { echo "FAIL: missing var bail note"; exit 1; }
echo "PASS: shell var bails"
