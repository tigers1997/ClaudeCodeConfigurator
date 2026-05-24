#!/usr/bin/env bash
# All 14 files declared in the discipline-skills module's paths list exist
# on disk. Catches drift between config_schema.py and the templates dir.
set -euo pipefail

paths=(
    "templates/discipline-skills/LICENSE"
    "templates/discipline-skills/brainstorming/SKILL.md"
    "templates/discipline-skills/brainstorming/spec-document-reviewer-prompt.md"
    "templates/discipline-skills/writing-plans/SKILL.md"
    "templates/discipline-skills/writing-plans/plan-document-reviewer-prompt.md"
    "templates/discipline-skills/executing-plans/SKILL.md"
    "templates/discipline-skills/verification-before-completion/SKILL.md"
    "templates/discipline-skills/using-git-worktrees/SKILL.md"
    "templates/discipline-skills/subagent-driven-development/SKILL.md"
    "templates/discipline-skills/subagent-driven-development/implementer-prompt.md"
    "templates/discipline-skills/subagent-driven-development/spec-reviewer-prompt.md"
    "templates/discipline-skills/subagent-driven-development/code-quality-reviewer-prompt.md"
    "templates/discipline-skills/finishing-a-development-branch/SKILL.md"
    "templates/discipline-skills/hooks/sessionstart-discipline.sh"
)

missing=0
for p in "${paths[@]}"; do
    if [ ! -f "$p" ]; then
        echo "FAIL: missing $p"
        missing=$((missing + 1))
    fi
done

[ "$missing" -eq 0 ] || exit 1

# Also assert the schema's paths list matches this test's expected list exactly.
schema_count=$(python3 -c "
import config_schema
for m in config_schema.MODULES:
    if m['id'] == 'discipline-skills':
        print(len(m['paths']))
        break
")
[ "$schema_count" = "${#paths[@]}" ] || {
    echo "FAIL: schema declares $schema_count paths, test expects ${#paths[@]}"
    exit 1
}

echo "PASS: all ${#paths[@]} discipline-skills files exist + schema count matches"
