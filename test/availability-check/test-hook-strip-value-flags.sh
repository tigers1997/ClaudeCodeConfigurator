#!/usr/bin/env bash
# Value-taking flags (-t bookworm-backports) should be skipped without consuming the package name.
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH"; exit 0
fi

# bash is known-present; if the parser mistakes "bookworm-backports" for a pkg, deny would fire.
input='{"tool_name":"Bash","tool_input":{"command":"apt install -t bookworm-backports bash"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc (expected 0; -t value was likely treated as pkg)"; echo "$out"; exit 1; }
[ -z "$out" ] || { echo "FAIL: unexpected output: $out"; exit 1; }
echo "PASS: -t <value> flag handled correctly"
