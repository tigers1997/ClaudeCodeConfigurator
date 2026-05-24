#!/usr/bin/env bash
# Pin the section anchors for verify-setup Check #12 (discipline-skills
# duplication detection) so future SKILL.md edits don't accidentally drop them.
set -euo pipefail
skill="templates/commands/verify-setup/SKILL.md"

required_anchors=(
    "### 12. Discipline-skills duplication"
    "_LICENSE-discipline-skills.md"
    "~/.claude/plugins/cache/*/superpowers"
    "Discipline skills: configurator's curated 7"
    "Discipline skills: BOTH installed"
    "Discipline skills: module not installed"
)

for anchor in "${required_anchors[@]}"; do
    grep -F -q "$anchor" "$skill" \
        || { echo "FAIL: missing anchor in $skill: '$anchor'"; exit 1; }
done

echo "PASS: Check #12 discipline-skills anchors present in verify-setup SKILL.md"
