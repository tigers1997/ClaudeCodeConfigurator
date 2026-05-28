#!/usr/bin/env bash
# apt install <nonexistent-pkg> → deny (exit 2) with structured stderr.
set -euo pipefail

HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH"; exit 0
fi

input='{"tool_name":"Bash","tool_input":{"command":"sudo apt install -y definitely-not-a-real-package-xyz123"}}'
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?

if [ "$rc" -ne 2 ]; then
  echo "FAIL: hook exited rc=$rc for missing pkg (expected 2)"; echo "stderr: $out"; exit 1
fi

# Required substrings.
for marker in \
  "[check-package-availability] DENIED" \
  "Command: apt install -y definitely-not-a-real-package-xyz123" \
  "Package manager: apt" \
  "Missing: definitely-not-a-real-package-xyz123" \
  "To proceed:"
do
  echo "$out" | grep -qF "$marker" || { echo "FAIL: stderr missing '$marker'"; echo "stderr was:"; echo "$out"; exit 1; }
done

echo "PASS: missing pkg → deny with structured stderr"
