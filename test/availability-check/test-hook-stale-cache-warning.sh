#!/usr/bin/env bash
# When apt cache lists/ is older than 7 days AND a deny fires, denial should include a stale-cache note.
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH"; exit 0
fi

# We can't easily override the real /var/lib/apt/lists/. Test the helper function
# in isolation by sourcing the hook with the stale-check function exposed.
# The hook's stale-check looks at $APT_LISTS_DIR (env override) with fallback to /var/lib/apt/lists.
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT
mkdir -p "$tmp/lists"
# Touch with mtime 10 days ago.
touch -d "10 days ago" "$tmp/lists"

# Run a denial scenario with APT_LISTS_DIR overridden.
input='{"tool_name":"Bash","tool_input":{"command":"apt install definitely-not-real-xyz123"}}'
out=$(printf '%s' "$input" | APT_LISTS_DIR="$tmp/lists" bash "$HOOK" 2>&1) && rc=$? || rc=$?

[ "$rc" -eq 2 ] || { echo "FAIL: rc=$rc (expected deny)"; exit 1; }
echo "$out" | grep -qE "apt cache is [0-9]+ days old" || { echo "FAIL: missing stale-cache warning"; echo "$out"; exit 1; }

# Now fresh cache → no warning.
touch "$tmp/lists"
out=$(printf '%s' "$input" | APT_LISTS_DIR="$tmp/lists" bash "$HOOK" 2>&1) && rc=$? || rc=$?
[ "$rc" -eq 2 ] || { echo "FAIL: rc=$rc on fresh-cache deny"; exit 1; }
if echo "$out" | grep -qE "apt cache is [0-9]+ days old"; then
  echo "FAIL: stale warning fired on fresh cache"; exit 1
fi
echo "PASS: stale-cache warning fires only when stale"
