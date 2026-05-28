#!/usr/bin/env bash
# When jq is not on PATH, hook should bail with stderr (not crash, not deny).
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

# If host doesn't have jq in /usr/bin, this test exercises the missing-jq path.
# If it does, the test is inconclusive; we treat that as a skip.
if command -v jq >/dev/null 2>&1 && [ -x /usr/bin/jq ]; then
  echo "SKIP: jq is in /usr/bin so the 'jq missing' path can't be exercised cleanly here"; exit 0
fi

input='{"tool_name":"Bash","tool_input":{"command":"apt install bash"}}'
out=$(printf '%s' "$input" | PATH=/usr/bin:/bin bash "$HOOK" 2>&1 | head -1) && rc=$? || rc=$?

[ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc when jq missing (expected 0 = bail)"; exit 1; }
echo "$out" | grep -q "jq missing" || { echo "FAIL: missing 'jq missing' note"; exit 1; }
echo "PASS: jq missing → bail with stderr"
