#!/usr/bin/env bash
# apt install <known-present-pkg> → silent allow.
set -euo pipefail

HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH"; exit 0
fi

input='{"tool_name":"Bash","tool_input":{"command":"sudo apt install -y bash"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL: hook exited rc=$rc for available pkg (expected 0)"; echo "stderr: $out"; exit 1
fi
if [ -n "$out" ]; then
  echo "FAIL: hook produced output for available pkg: '$out'"; exit 1
fi
echo "PASS: apt install bash → silent allow"
