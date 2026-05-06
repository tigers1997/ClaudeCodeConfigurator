#!/usr/bin/env bash
# Output cleanup checks:
#   - all "wrote" lines come before "saved config" (no interleaving)
#   - .gitignore line shows actual patterns inline, not just a count
#   - 3 MCP profile alternates render as one labeled group, not 3 lines
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

out=$(python3 configure.py --persona solo-experienced --yes --dir "$tmp" 2>&1)

# Ordering: every "wrote" line index < the one "saved config" line index.
saved_idx=$(echo "$out" | grep -n "saved config to" | head -1 | cut -d: -f1)
[ -n "$saved_idx" ] || { echo "FAIL: no 'saved config' line found"; exit 1; }
last_wrote_idx=$(echo "$out" | grep -n "wrote" | tail -1 | cut -d: -f1 || echo "0")
[ "$last_wrote_idx" -lt "$saved_idx" ] || { echo "FAIL: 'wrote' (line $last_wrote_idx) appeared after 'saved config' (line $saved_idx)"; echo "---"; echo "$out"; exit 1; }

# .gitignore line should list at least one pattern in parens.
echo "$out" | grep -qE "\.gitignore: append [0-9]+ rules \(" \
    || { echo "FAIL: .gitignore line missing inline patterns"; echo "---"; echo "$out" | grep gitignore; exit 1; }

# MCP profile alternates: should appear as a single labeled group line,
# not as three separate "wrote" lines.
mcp_alt_lines=$(echo "$out" | grep -cE "wrote +\.mcp\.(minimal|frontend|research)\.json" || true)
[ "$mcp_alt_lines" = "0" ] || { echo "FAIL: MCP profile alternates printed as separate 'wrote' lines ($mcp_alt_lines found); expected a single grouped line"; exit 1; }
echo "$out" | grep -qE "MCP profile alternates" \
    || { echo "FAIL: missing 'MCP profile alternates' grouped line"; echo "---"; echo "$out" | grep -i mcp; exit 1; }

echo "PASS: output ordering, gitignore detail, MCP grouping all clean"
