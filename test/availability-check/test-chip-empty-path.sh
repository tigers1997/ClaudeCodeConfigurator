#!/usr/bin/env bash
# With minimal PATH (no pg/node/python/docker), chip should be empty or just OS.
set -euo pipefail

LIB="$PWD/templates/safety/hooks/_lib/detect_tool_versions.sh"

# Use a PATH with no real tools at all (just bash builtins). All `command -v`
# checks for pg_config/node/python3/docker should fail, so chip is OS-only.
# _chip_os uses bash builtins + /etc/os-release direct read — no externals needed.
# Use absolute bash path because PATH assignment applies to the bash lookup itself.
BASH_BIN=$(command -v bash)
result=$(PATH=/nonexistent "$BASH_BIN" -c "source '$LIB' && emit_version_chip")

# OS chip is expected to appear (parsed from /etc/os-release on Linux).
# Tool chips should NOT appear (pg_config/node/python3/docker not on this PATH).
echo "got: '$result'"
if echo "$result" | grep -qE 'pg[0-9]|node[0-9]|py[0-9]|docker[0-9]'; then
  echo "FAIL: chip contains tool version despite empty tool PATH: '$result'"; exit 1
fi
echo "PASS: empty-tool-PATH chip omits tool versions (OS chip OK)"
