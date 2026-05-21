#!/usr/bin/env bash
# Pin the section anchors so future SKILL.md edits don't accidentally drop
# the new §4b / §4c narrative.
set -euo pipefail
skill="templates/commands/verify-setup/SKILL.md"

required_anchors=(
    "### 4b. Stack drift"
    "### 4c. Command alignment"
    "Stack drift: 0 changes since baseline"
    "Stack drift:"
    "Command alignment: configured tools match current stack"
    "Command alignment:"
    "cc-configure --retrofit"
)

for anchor in "${required_anchors[@]}"; do
    grep -F -q "$anchor" "$skill" \
        || { echo "FAIL: missing anchor in $skill: '$anchor'"; exit 1; }
done

echo "PASS: §4b + §4c anchors present in verify-setup SKILL.md"
