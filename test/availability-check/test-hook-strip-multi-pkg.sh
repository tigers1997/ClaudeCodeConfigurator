#!/usr/bin/env bash
# Multi-pkg install with one valid + one missing should deny only when missing exists.
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH"; exit 0
fi

# Two valid pkgs → allow.
input='{"tool_name":"Bash","tool_input":{"command":"apt install -y bash coreutils"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc for two valid pkgs"; exit 1; }
[ -z "$out" ] || { echo "FAIL: output on valid pkgs: $out"; exit 1; }

# One valid + one missing → deny, missing list should contain only the bad one.
input='{"tool_name":"Bash","tool_input":{"command":"apt install -y bash definitely-not-real-xyz123"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: rc=$rc for valid+missing (expected 2)"; exit 1; }
echo "$out" | grep -q "Missing: definitely-not-real-xyz123" || { echo "FAIL: missing list should not include 'bash'"; echo "$out"; exit 1; }
echo "$out" | grep -q "Missing: bash" && { echo "FAIL: 'bash' incorrectly listed as missing"; exit 1; }
echo "PASS: multi-pkg handled (valid passes; mixed denies with correct missing list)"
