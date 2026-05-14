#!/usr/bin/env bash
# Rendered verify-setup SKILL.md must include the rewritten Check #4 with
# manifest-aware drift narrative, Sonatype MCP vetting nudge, profile-split
# guidance, and the cc-configure --retrofit accept-baseline mention.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
sk="$tmp/.claude/skills/verify-setup/SKILL.md"
[ -f "$sk" ] || { echo "FAIL: SKILL.md not scaffolded at $sk"; exit 1; }

# Required anchors in the new Check #4
required=(
    'MCP overhead \+ drift'
    'Drift check'
    'manifest_version'
    'cc-configure --retrofit'
    '\.mcp\.<profile>\.json'
    'Sonatype'
    'getRecommendedComponentVersions'
    'getComponentVersion'
    'Supply-chain nudge'
)
for pat in "${required[@]}"; do
    grep -qE "$pat" "$sk" \
        || { echo "FAIL: anchor missing — '$pat'"; exit 1; }
done

# allowed-tools must still include the bash invocations the skill depends on
grep -qE '^allowed-tools:.*Bash\(jq:\*\)' "$sk" \
    || { echo "FAIL: allowed-tools lacks Bash(jq:*)"; grep '^allowed-tools' "$sk"; exit 1; }

echo "PASS: verify-setup Check #4 ships all drift-monitor anchors"
