#!/usr/bin/env bash
# With CC_STATUSLINE_NO_VERSION_CHIP=1 env, chip is omitted.
set -euo pipefail

STATUSLINE="$PWD/templates/ui/statusline.sh"
LIB_SRC="$PWD/templates/safety/hooks/_lib/detect_tool_versions.sh"

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT
mkdir -p "$tmp/.claude/hooks/_lib"
cp "$LIB_SRC" "$tmp/.claude/hooks/_lib/detect_tool_versions.sh"

input='{"model":{"display_name":"sonnet-4-6"},"cwd":"'"$tmp"'","usage":{"context":{"used_pct":12}}}'
out=$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$tmp" CC_STATUSLINE_NO_VERSION_CHIP=1 bash "$STATUSLINE" 2>&1)
plain=$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g')
echo "got: $plain"

# Chip should NOT appear (no OS/tool token after a final separator).
if echo "$plain" | grep -qE '\|[[:space:]]+(deb|ubuntu|mac|fedora|arch|alpine)[0-9]'; then
  echo "FAIL: chip present despite opt-out"; exit 1
fi
if echo "$plain" | grep -qE '\|[[:space:]]+(pg|node|py|docker)[0-9]'; then
  echo "FAIL: tool chip present despite opt-out"; exit 1
fi
echo "PASS: chip omitted when CC_STATUSLINE_NO_VERSION_CHIP=1"
