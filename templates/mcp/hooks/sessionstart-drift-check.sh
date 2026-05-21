#!/usr/bin/env bash
# cc-configure SessionStart drift monitor.
# Reads .claude/.cc-manifest.json (cc-configure scaffold baseline) and .mcp.json
# (current MCP servers); emits one stdout line if the MCP set differs since
# the last cc-configure run. Silent otherwise.
#
# Performance budget: <50ms warm cache. Two small JSON reads + comm diff; no
# subshells beyond jq invocations.
#
# Failure discipline: never break session start. Any unexpected condition
# (missing tool, malformed JSON, unreadable file) → exit 0 silently. The only
# non-silent output paths are (a) actual drift summary, (b) one-line note
# when manifest_version is newer than this hook understands.
set -uo pipefail

# Resolve project root
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MANIFEST="$ROOT/.claude/.cc-manifest.json"
MCP="$ROOT/.mcp.json"

# No manifest → nothing to compare
[ -f "$MANIFEST" ] || exit 0

# Require jq; if missing, fail silent
command -v jq >/dev/null 2>&1 || exit 0

# Check manifest_version. Hook understands v1 (read-only — skips new dimensions)
# and v2 (full drift narrative). v3+ → emit one-line upgrade nudge and exit.
mv=$(jq -r '.manifest_version // empty' "$MANIFEST" 2>/dev/null)
if [ -z "$mv" ]; then
    # Manifest malformed or missing key — silent
    exit 0
fi
case "$mv" in
    1|2) ;;
    *)
        echo "cc-configure: manifest version $mv detected; this hook is v2 — please update cc-configure."
        exit 0
        ;;
esac

# Read baseline MCP server keys (sorted)
baseline=$(jq -r '.mcp_servers[]?' "$MANIFEST" 2>/dev/null | LC_ALL=C sort -u)

# Read current MCP server keys (sorted, filtering // comment keys)
if [ -f "$MCP" ]; then
    current=$(jq -r '.mcpServers // {} | keys[] | select(startswith("//") | not)' "$MCP" 2>/dev/null | LC_ALL=C sort -u)
    # If jq failed (malformed .mcp.json), current will be empty and we'd
    # report removals — but that's a lie. Detect parse failure explicitly.
    if ! jq -e '.' "$MCP" >/dev/null 2>&1; then
        exit 0
    fi
else
    current=""
fi

# Diff: added = in current but not in baseline; removed = in baseline but not in current.
added=$(comm -13 <(echo "$baseline") <(echo "$current") | sed '/^$/d')
removed=$(comm -23 <(echo "$baseline") <(echo "$current") | sed '/^$/d')

# No drift → silent
if [ -z "$added" ] && [ -z "$removed" ]; then
    exit 0
fi

# Build one-line summary
parts=()
if [ -n "$added" ]; then
    n=$(echo "$added" | wc -l | tr -d ' ')
    names=$(echo "$added" | paste -s -d , - | sed 's/,/, /g')
    parts+=("$n added ($names)")
fi
if [ -n "$removed" ]; then
    n=$(echo "$removed" | wc -l | tr -d ' ')
    names=$(echo "$removed" | paste -s -d , - | sed 's/,/, /g')
    parts+=("$n removed ($names)")
fi

# Join parts with " / "
joined=""
sep=""
for p in "${parts[@]}"; do
    joined="${joined}${sep}${p}"
    sep=" / "
done
echo "cc-configure: MCP drift since last cc-configure run — $joined. Run /verify-setup for tradeoffs."
exit 0
