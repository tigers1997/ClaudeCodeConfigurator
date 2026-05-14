#!/usr/bin/env bash
# If .mcp.json is malformed on a retrofit run, write_cc_manifest must:
# (a) NOT overwrite an existing valid manifest, (b) emit a [ MANIFEST WARNINGS ]
# line on stdout naming the problem.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Initial scaffold creates a valid manifest.
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
manifest="$tmp/.claude/.cc-manifest.json"
[ -f "$manifest" ] || { echo "FAIL: initial manifest missing"; exit 1; }
cp "$manifest" "$manifest.before"

# Corrupt the .mcp.json the persona just provisioned.
echo "{ this is not valid JSON" > "$tmp/.mcp.json"

# Retrofit run — capture stdout to check for the warning block.
out=$(python3 configure.py --persona solo-experienced --yes --dir "$tmp" 2>&1)

# Warning must surface
echo "$out" | grep -q "MANIFEST WARNINGS" \
    || { echo "FAIL: [ MANIFEST WARNINGS ] header not emitted"; echo "$out"; exit 1; }
echo "$out" | grep -q ".mcp.json is not valid JSON" \
    || { echo "FAIL: warning text missing 'not valid JSON'"; echo "$out"; exit 1; }

# Existing manifest must NOT have been clobbered with a corrupt baseline.
diff "$manifest" "$manifest.before" >/dev/null \
    || { echo "FAIL: manifest was overwritten despite malformed .mcp.json"; exit 1; }

echo "PASS: malformed .mcp.json triggers [ MANIFEST WARNINGS ] + preserves prior manifest"
