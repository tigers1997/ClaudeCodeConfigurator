#!/usr/bin/env bash
# `apt update` (non-install subcmd) should pass through silently.
set -euo pipefail

HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

input='{"tool_name":"Bash","tool_input":{"command":"sudo apt update"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL: hook exited rc=$rc on 'apt update' (expected 0)"; exit 1
fi
if [ -n "$out" ]; then
  echo "FAIL: hook produced output on 'apt update': '$out'"; exit 1
fi
echo "PASS: sudo apt update → silent allow"
