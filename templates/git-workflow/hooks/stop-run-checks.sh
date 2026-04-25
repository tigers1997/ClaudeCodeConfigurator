#!/usr/bin/env bash
# Stop hook — runs the typecheck / lint / test commands you configured during
# cc-configure intake. Reports results to Claude via additionalContext on the
# next turn; never blocks.
#
# Skipping rules (silent, not reported):
#   1. Empty command — you blanked the field in the form (e.g., "I don't have
#      a typecheck setup"). Edit .claude-config.json or rerun cc-configure to
#      add one later.
#   2. First binary not on PATH at runtime — e.g., `uv` isn't installed yet
#      on this machine. Defensive guard so a missing tool doesn't generate
#      noise; the underlying intent of the check is still configured.
#
# Customize the CHECKS block below if you want a different set of commands or
# labels. The placeholder values are populated from your cc-configure form
# answers, but the file is yours to edit freely after scaffolding.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR"

# label|command — labels are display-only, commands come from cc-configure.
# Leave a value empty after the `|` to skip that check entirely.
CHECKS=(
  "typecheck|{{cmd_typecheck}}"
  "lint|{{cmd_lint}}"
  "test|{{cmd_test}}"
)

REPORT=""
for entry in "${CHECKS[@]}"; do
  label="${entry%%|*}"
  cmd="${entry#*|}"

  # Skip empty (user opted out of this check during intake).
  [ -z "$cmd" ] && continue

  # Skip if the first binary in the command isn't on PATH.
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
