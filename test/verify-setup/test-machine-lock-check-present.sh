#!/usr/bin/env bash
# Pin the anchors for verify-setup check 17 (the machine lock: updater off,
# auto mode out of the Shift+Tab cycle, plan mode prompting) and the docs/11
# section it points at, so a SKILL.md or docs edit cannot silently drop the
# half of the discipline profile a repository cannot pin.
set -euo pipefail
skill="templates/commands/verify-setup/SKILL.md"
doc="docs/11-getting-started.md"

skill_anchors=(
    "### 17. Machine lock"
    "DISABLE_AUTOUPDATER"
    "disableAutoMode"
    "useAutoModeDuringPlan"
    "claude doctor"
    "Auto-updates:"
    "Auto mode:"
    "Plan mode:"
    "Once per machine"
)
for anchor in "${skill_anchors[@]}"; do
    grep -F -q "$anchor" "$skill" \
        || { echo "FAIL: missing anchor in $skill: '$anchor'"; exit 1; }
done

doc_anchors=(
    "## Once per machine"
    '"DISABLE_AUTOUPDATER": "1"'
    '"autoUpdatesChannel": "stable"'
    '"disableAutoMode": "disable"'
    '"useAutoModeDuringPlan": false'
    "claudeCode.initialPermissionMode"
    "requiredMaximumVersion"
    "cc-configure --whats-new"
)
for anchor in "${doc_anchors[@]}"; do
    grep -F -q "$anchor" "$doc" \
        || { echo "FAIL: missing anchor in $doc: '$anchor'"; exit 1; }
done

# Every entry point links to the section: the README's Install section, and the
# quickstart, greenfield and retrofit flows inside docs/11.
grep -F -q "docs/11-getting-started.md#once-per-machine" README.md \
    || { echo "FAIL: README does not link to the once-per-machine section"; exit 1; }
links=$(grep -c -F "(#once-per-machine)" "$doc")
[ "$links" -ge 3 ] \
    || { echo "FAIL: docs/11 links #once-per-machine $links time(s); the quickstart, greenfield and retrofit flows should each link it"; exit 1; }

echo "PASS: verify-setup check 17 and the once-per-machine docs anchors are present"
