#!/usr/bin/env bash
# A command that isn't apt/brew/dnf/yum/pacman/apk should pass through silently.
set -euo pipefail

HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

input='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL: hook exited rc=$rc on non-PM command (expected 0)"; exit 1
fi
if [ -n "$out" ]; then
  echo "FAIL: hook produced output on non-PM command: '$out'"; exit 1
fi
echo "PASS: ls -la → silent allow"
