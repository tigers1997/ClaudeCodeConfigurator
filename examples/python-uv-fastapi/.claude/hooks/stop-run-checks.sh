#!/usr/bin/env bash
# Stop hook — runs lint + typecheck + fast tests when a turn finishes.
# Only reports; never blocks. Output shown to Claude on the next turn via additionalContext.
#
# Customize CHECKS below for your project.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR"

# Declare checks as "label|command" pairs. First one present wins.
CHECKS=(
  "typecheck|npx --no-install tsc --noEmit"
  "lint|npx --no-install eslint . --max-warnings=0"
  "test|npx --no-install vitest run --reporter=dot --changed"
)

REPORT=""
for entry in "${CHECKS[@]}"; do
  label="${entry%%|*}"
  cmd="${entry#*|}"
  # Skip if the first binary in the command isn't available.
  first="$(printf '%s' "$cmd" | awk '{print $1}')"
  if ! command -v "$first" >/dev/null 2>&1; then continue; fi

  out=$(eval "$cmd" 2>&1) && status=0 || status=$?
  if [ $status -eq 0 ]; then
    REPORT="${REPORT}[stop-check] ${label}: OK"$'\n'
  else
    tail=$(printf '%s' "$out" | tail -n 30)
    REPORT="${REPORT}[stop-check] ${label}: FAIL (exit ${status})"$'\n'"${tail}"$'\n---\n'
  fi
done

# Emit decision JSON so Claude sees the report on the next turn.
if [ -n "$REPORT" ]; then
  jq -n --arg ctx "$REPORT" '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":$ctx}}'
fi
exit 0
