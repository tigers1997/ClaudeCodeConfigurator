#!/usr/bin/env bash
# Every SKILL.md in discipline-skills has YAML frontmatter with `name:` and
# `description:` keys, and the name matches the parent directory.
set -euo pipefail

cd templates/discipline-skills

fail=0
for skill in */SKILL.md; do
    dir=$(dirname "$skill")
    # Frontmatter present?
    head -1 "$skill" | grep -q '^---$' || { echo "FAIL: $skill no opening ---"; fail=1; continue; }
    # name: matches dir
    name=$(grep -m1 '^name:' "$skill" | sed -E 's/^name:[[:space:]]*//; s/[[:space:]]*$//')
    [ "$name" = "$dir" ] || { echo "FAIL: $skill name=$name but dir=$dir"; fail=1; }
    # description: present and non-empty
    desc=$(grep -m1 '^description:' "$skill" | sed -E 's/^description:[[:space:]]*//' || true)
    [ -n "$desc" ] || { echo "FAIL: $skill missing or empty description"; fail=1; }
done

[ "$fail" -eq 0 ] || exit 1
echo "PASS: all SKILL.md frontmatter valid (name matches dir, description present)"
