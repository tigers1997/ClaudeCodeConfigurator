#!/usr/bin/env bash
# When _lib/detect_tool_versions.sh is on the expected absolute path and emits a chip,
# statusline output should include the chip prefixed by " | ".
set -euo pipefail

STATUSLINE="$PWD/templates/ui/statusline.sh"
LIB_SRC="$PWD/templates/safety/hooks/_lib/detect_tool_versions.sh"

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT
mkdir -p "$tmp/.claude/hooks/_lib"
cp "$LIB_SRC" "$tmp/.claude/hooks/_lib/detect_tool_versions.sh"

# Real statusline stdin shape: { model.display_name, cwd, usage.context.used_pct }
input='{"model":{"display_name":"sonnet-4-6"},"cwd":"'"$tmp"'","usage":{"context":{"used_pct":12}}}'
out=$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$tmp" bash "$STATUSLINE" 2>&1)
echo "got: $out"

# Strip ANSI for matching.
plain=$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g')

# Chip should appear after a " | " separator and contain at least one tool/OS marker.
echo "$plain" | grep -qE '\|[[:space:]]+[a-z]+[0-9]' || { echo "FAIL: no chip-like suffix in plain: $plain"; exit 1; }
echo "PASS: statusline includes version chip"
