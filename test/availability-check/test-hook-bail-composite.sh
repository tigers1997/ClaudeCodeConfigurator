#!/usr/bin/env bash
# Composite shell expressions should bail (exit 0 + stderr note).
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

for cmd in \
  "apt install x | tee /tmp/out" \
  "apt install x && echo done" \
  "apt install x ; echo done" \
  "apt install \$(echo x)" \
  "apt install \`echo x\`"
do
  input=$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc for '$cmd' (expected 0)"; exit 1; }
  echo "$out" | grep -q "composite shell expression" || { echo "FAIL: missing bail note for '$cmd'"; exit 1; }
done
echo "PASS: composite expressions all bail"
