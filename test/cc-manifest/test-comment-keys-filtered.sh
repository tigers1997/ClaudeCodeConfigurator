#!/usr/bin/env bash
# // keys in mcpServers are excluded from the manifest. We pre-write a
# .mcp.json with a comment key, then run retrofit to trigger a manifest
# rewrite over the existing scaffolded one.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Initial scaffold so .claude/ exists.
python3 configure.py --persona library-author --yes --dir "$tmp" >/dev/null

# Replace .mcp.json with a fixture containing a comment key.
cat > "$tmp/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "//comment": "this is a documentation key, not a real server",
    "real-server": { "command": "echo" }
  }
}
EOF

# Retrofit triggers a fresh manifest write (we test retrofit semantics later;
# here we only care that the helper re-reads the file and filters correctly).
python3 configure.py --persona library-author --yes --dir "$tmp" >/dev/null

manifest="$tmp/.claude/.cc-manifest.json"
servers=$(jq -r '.mcp_servers[]' "$manifest" | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//')

[ "$servers" = "real-server" ] \
    || { echo "FAIL: comment key not filtered — got '$servers'"; exit 1; }

echo "PASS: // comment keys filtered out of manifest"
