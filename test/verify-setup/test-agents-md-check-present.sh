#!/usr/bin/env bash
# verify-setup check 18 (the AGENTS.md bridge and the Codex 32 KiB budget) must
# survive SKILL.md edits, because the numbers and the import line are what make
# the check correct: Claude Code reads AGENTS.md only when no CLAUDE.md exists,
# and Codex silently truncates its AGENTS.md chain at 32768 bytes.
set -euo pipefail

skill="templates/commands/verify-setup/SKILL.md"
anchors=(
    "### 18. Cross-harness instructions"
    "@AGENTS.md"
    "@./AGENTS.md"
    "project_doc_max_bytes"
    "32768"
    "24576"
    "context.fileName"
    "AGENTS.md bridge:"
    "AGENTS.md budget:"
    "count \`AGENTS.md\` too"
)
for anchor in "${anchors[@]}"; do
    grep -F -q -- "$anchor" "$skill" \
        || { echo "FAIL: missing anchor in $skill: '$anchor'"; exit 1; }
done

# The check ships: a scaffold carries it (it is a no-op unless AGENTS.md exists).
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 configure.py --persona solo-newer --yes --dir "$tmp" >/dev/null
grep -q '^### 18\. Cross-harness instructions$' "$tmp/.claude/skills/verify-setup/SKILL.md" \
    || { echo "FAIL: rendered verify-setup lacks check 18"; exit 1; }

# `wc -c` is how the budget is sized, so the skill must be allowed to run it.
grep -qE '^allowed-tools:.*Bash\(wc:\*\)' "$tmp/.claude/skills/verify-setup/SKILL.md" \
    || { echo "FAIL: verify-setup is not allowed to run wc"; exit 1; }

echo "PASS: verify-setup check 18 anchors are present and ship in the scaffold"
