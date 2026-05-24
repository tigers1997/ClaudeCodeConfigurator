#!/usr/bin/env bash
# Scaffolding with the discipline-skills module installs all 7 skill dirs
# at .claude/skills/ + the bootstrap hook at .claude/hooks/ + the LICENSE
# attribution + the SessionStart hook registration in settings.json.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# solo-experienced persona includes discipline-skills by default.
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

# 7 skill dirs each with SKILL.md
for skill in brainstorming writing-plans executing-plans verification-before-completion using-git-worktrees subagent-driven-development finishing-a-development-branch; do
    [ -f "$tmp/.claude/skills/$skill/SKILL.md" ] \
        || { echo "FAIL: missing $tmp/.claude/skills/$skill/SKILL.md"; exit 1; }
done

# LICENSE attribution
[ -f "$tmp/.claude/skills/_LICENSE-discipline-skills.md" ] \
    || { echo "FAIL: missing LICENSE attribution"; exit 1; }
grep -q "Jesse Vincent" "$tmp/.claude/skills/_LICENSE-discipline-skills.md" \
    || { echo "FAIL: LICENSE missing upstream copyright"; exit 1; }

# Bootstrap hook
[ -f "$tmp/.claude/hooks/sessionstart-discipline.sh" ] \
    || { echo "FAIL: missing bootstrap hook"; exit 1; }
[ -x "$tmp/.claude/hooks/sessionstart-discipline.sh" ] \
    || { echo "FAIL: bootstrap hook not executable"; exit 1; }

# SessionStart hook wired in settings.json
jq -e '.hooks.SessionStart[] | .hooks[] | select(.command | contains("sessionstart-discipline.sh"))' \
    "$tmp/.claude/settings.json" >/dev/null \
    || { echo "FAIL: bootstrap hook not registered in settings.json"; exit 1; }

# Supporting prompt files for skills that have them
[ -f "$tmp/.claude/skills/brainstorming/spec-document-reviewer-prompt.md" ] \
    || { echo "FAIL: missing brainstorming/spec-document-reviewer-prompt.md"; exit 1; }
[ -f "$tmp/.claude/skills/writing-plans/plan-document-reviewer-prompt.md" ] \
    || { echo "FAIL: missing writing-plans/plan-document-reviewer-prompt.md"; exit 1; }
for sub in implementer-prompt.md spec-reviewer-prompt.md code-quality-reviewer-prompt.md; do
    [ -f "$tmp/.claude/skills/subagent-driven-development/$sub" ] \
        || { echo "FAIL: missing subagent-driven-development/$sub"; exit 1; }
done

echo "PASS: scaffold installs all skills, hook, LICENSE, and settings registration"
