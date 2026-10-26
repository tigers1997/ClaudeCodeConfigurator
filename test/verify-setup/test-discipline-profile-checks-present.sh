#!/usr/bin/env bash
# Pin the section anchors for verify-setup checks 14-16 (the discipline
# profile: pinned starting mode, the two env vars, account skill sync) so
# future SKILL.md edits don't accidentally drop them.
set -euo pipefail
skill="templates/commands/verify-setup/SKILL.md"

required_anchors=(
    "### 14. Starting mode pinned"
    "permissions.defaultMode"
    "claudeCode.initialPermissionMode"
    "### 15. Discipline env vars"
    "CLAUDE_CODE_FORK_SUBAGENT"
    "CLAUDE_CODE_ENABLE_TODO_TOOLS"
    "### 16. Account skill sync"
    "syncClaudeAiSkills"
    "~/.claude/skills/synced"
    "Starting mode:"
    "Discipline env:"
    "Account skill sync:"
)

for anchor in "${required_anchors[@]}"; do
    grep -F -q "$anchor" "$skill" \
        || { echo "FAIL: missing anchor in $skill: '$anchor'"; exit 1; }
done

echo "PASS: checks 14-16 discipline-profile anchors present in verify-setup SKILL.md"
