#!/usr/bin/env bash
# sudo and ENV=val prefixes should be stripped cleanly.
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH"; exit 0
fi

for cmd in \
  "sudo apt install -y bash" \
  "DEBIAN_FRONTEND=noninteractive apt install -y bash" \
  "DEBIAN_FRONTEND=noninteractive sudo -E apt install -y bash"
do
  input=$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: rc=$rc for '$cmd' (expected 0 = allow)"; echo "$out"; exit 1; }
  [ -z "$out" ] || { echo "FAIL: unexpected output for '$cmd': $out"; exit 1; }
done
echo "PASS: sudo + env-var prefixes stripped correctly"
