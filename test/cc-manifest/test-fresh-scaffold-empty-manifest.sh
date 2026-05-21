#!/usr/bin/env bash
# Fresh scaffold (no .mcp.json from user) → manifest exists at
# .claude/.cc-manifest.json with mcp_servers: []
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# library-author persona omits the mcp module → no .mcp.json gets scaffolded.
python3 configure.py --persona library-author --yes --dir "$tmp" >/dev/null

manifest="$tmp/.claude/.cc-manifest.json"
[ -f "$manifest" ] || { echo "FAIL: manifest not written at $manifest"; exit 1; }

# Required fields present
jq -e '.manifest_version == 2' "$manifest" >/dev/null \
    || { echo "FAIL: manifest_version != 2"; cat "$manifest"; exit 1; }
jq -e '.mcp_servers == []' "$manifest" >/dev/null \
    || { echo "FAIL: mcp_servers not empty"; cat "$manifest"; exit 1; }
jq -e '.stack_manifests | type == "array"' "$manifest" >/dev/null \
    || { echo "FAIL: stack_manifests not an array"; cat "$manifest"; exit 1; }
jq -e '.check_commands | type == "object"' "$manifest" >/dev/null \
    || { echo "FAIL: check_commands not an object"; cat "$manifest"; exit 1; }
jq -e '.written_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$manifest" >/dev/null \
    || { echo "FAIL: written_at not ISO 8601 UTC"; cat "$manifest"; exit 1; }
jq -e '.written_by | startswith("cc-configure ")' "$manifest" >/dev/null \
    || { echo "FAIL: written_by missing cc-configure prefix"; cat "$manifest"; exit 1; }

echo "PASS: fresh scaffold writes empty-baseline manifest"
