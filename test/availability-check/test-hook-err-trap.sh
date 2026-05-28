#!/usr/bin/env bash
# Malformed JSON should bail (not crash, not deny).
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

out=$(printf 'not valid json' | bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc on malformed JSON (expected 0)"; echo "$out"; exit 1; }
echo "PASS: malformed JSON → silent bail"
