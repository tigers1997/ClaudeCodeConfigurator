#!/usr/bin/env bash
# Bootstrap hook emits valid JSON with the expected bootstrap content.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Run hook with a fake CLAUDE_PROJECT_DIR and no superpowers plugin in HOME.
out=$(HOME="$tmp" CLAUDE_PROJECT_DIR="$tmp" bash templates/discipline-skills/hooks/sessionstart-discipline.sh)

# Must be non-empty
[ -n "$out" ] || { echo "FAIL: hook produced no output"; exit 1; }

# Must be valid JSON
echo "$out" | jq -e '.' >/dev/null || { echo "FAIL: hook output not valid JSON: $out"; exit 1; }

# Must contain the additionalContext (Claude Code form, since CLAUDE_PROJECT_DIR is set)
echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null \
    || { echo "FAIL: hookEventName not SessionStart"; exit 1; }
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null \
    || { echo "FAIL: additionalContext empty"; exit 1; }

# Bootstrap content must mention the 7 skills (sanity check)
ctx=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext')
for skill in brainstorming writing-plans executing-plans verification-before-completion using-git-worktrees subagent-driven-development finishing-a-development-branch; do
    echo "$ctx" | grep -q "$skill" || { echo "FAIL: bootstrap missing '$skill'"; exit 1; }
done

echo "PASS: hook emits valid JSON with all 7 skill names in additionalContext"
