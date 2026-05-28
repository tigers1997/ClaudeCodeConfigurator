#!/usr/bin/env bash
# Fixture test for templates/safety/hooks/block-dangerous-bash.sh
#
# Regression guard for the trailing-slash / $HOME bypass class that Claude Code
# itself fixed in 2.1.154 ("rm -rf $HOME not blocked when HOME has a trailing
# slash"). The configurator's guard had the same blind spot: the ~ and / anchors
# stopped matching the moment a trailing slash followed, and the $HOME variable
# form was never matched at all.
set -euo pipefail

HOOK=templates/safety/hooks/block-dangerous-bash.sh

# Each of these wipes a home/root tree and MUST be blocked (hook exits non-zero).
SHOULD_BLOCK=(
  'rm -rf ~'            # bare home (already covered)
  'rm -rf ~/'          # home + trailing slash (the 2.1.154 bypass)
  'rm -rf /'           # bare root (already covered)
  'rm -rf //'          # root + extra slash
  'rm -rf $HOME'       # variable form
  'rm -rf $HOME/'      # variable form + trailing slash
  'rm -rf "$HOME"/'    # quoted variable form + trailing slash
)

# Each of these targets a subdirectory and MUST be allowed (hook exits 0) so the
# widened patterns don't become over-broad and block legitimate cleanups.
SHOULD_ALLOW=(
  'rm -rf ~/myproject/node_modules'
  'rm -rf $HOME/tmp'
  'rm -rf ./build'
  'rm -rf node_modules'
)

fail=0

for cmd in "${SHOULD_BLOCK[@]}"; do
  payload=$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')
  if printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1; then
    echo "FAIL: should have blocked: $cmd"; fail=1
  fi
done

for cmd in "${SHOULD_ALLOW[@]}"; do
  payload=$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')
  if ! printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1; then
    echo "FAIL: should have allowed: $cmd"; fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "FAIL: block-dangerous-bash trailing-slash/\$HOME coverage incomplete"; exit 1
fi
echo "PASS: block-dangerous-bash blocks home/root wipes (incl. trailing slash + \$HOME) and allows subdir cleanups"
