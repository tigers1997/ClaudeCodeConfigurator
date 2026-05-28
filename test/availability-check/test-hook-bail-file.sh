#!/usr/bin/env bash
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

for cmd in \
  "apt install ./local.deb" \
  "dnf install /tmp/pkg.rpm" \
  "apk add /var/cache/foo.apk"
do
  input=$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc for '$cmd' (expected 0)"; exit 1; }
  echo "$out" | grep -qE "(file install|local archive)" || { echo "FAIL: missing file bail note for '$cmd'"; exit 1; }
done
echo "PASS: file installs all bail"
