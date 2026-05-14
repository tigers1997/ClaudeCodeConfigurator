#!/usr/bin/env bash
# When mcp module is selected, the scaffolded .mcp.json's keys land in the
# manifest sorted. Uses solo-experienced persona (includes mcp module with
# context7 + git enabled).
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

manifest="$tmp/.claude/.cc-manifest.json"
mcp="$tmp/.mcp.json"

[ -f "$manifest" ] || { echo "FAIL: manifest missing"; exit 1; }
[ -f "$mcp" ] || { echo "FAIL: .mcp.json missing (persona should have provisioned it)"; exit 1; }

# Capture sorted server keys present in the scaffolded .mcp.json (filtering
# // comment keys — same rule the helper applies).
expected=$(jq -r '.mcpServers // {} | keys[] | select(startswith("//") | not)' "$mcp" | LC_ALL=C sort)
actual=$(jq -r '.mcp_servers[]' "$manifest")

# Manifest list should equal the .mcp.json key set
if [ "$actual" != "$expected" ]; then
    echo "FAIL: manifest mcp_servers != .mcp.json keys"
    echo "expected: $expected"
    echo "actual:   $actual"
    exit 1
fi

# And it must be sorted
sorted=$(echo "$actual" | LC_ALL=C sort)
[ "$actual" = "$sorted" ] || { echo "FAIL: mcp_servers not sorted"; exit 1; }

echo "PASS: manifest reflects scaffolded .mcp.json keys (sorted)"
