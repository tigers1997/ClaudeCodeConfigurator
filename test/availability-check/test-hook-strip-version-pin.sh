#!/usr/bin/env bash
# Version pins (pkg=1.2.3 / pkg@1.2.3) should be stripped before the availability check.
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH"; exit 0
fi

# Use a deliberately-pinned but real package name; bash always exists.
input='{"tool_name":"Bash","tool_input":{"command":"apt install bash=5.99.99-fakeversion"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc for pinned bash (expected 0 = allow; pin should strip)"; echo "$out"; exit 1; }
[ -z "$out" ] || { echo "FAIL: unexpected output: $out"; exit 1; }
echo "PASS: version pin stripped correctly"
