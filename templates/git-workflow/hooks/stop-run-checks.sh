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
#   3. Stack manifest missing — e.g., `pnpm test` configured but no
#      package.json exists yet. Typical when the project is still in the
#      brainstorming/planning phase before any code lands. Mapping lives in
#      manifest_for() below; tools not in the map (tsc, pytest, ruff, …)
#      have no guard and run unconditionally.
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

# Map the first binary of a check command to the manifest file that signals
# "this stack has been scaffolded." Empty string means "no manifest guard;
# run the command and let it surface its own errors." Add entries as new
# stacks gain support — POSIX case keeps macOS bash 3.2 happy.
manifest_for() {
  case "$1" in
    pnpm|npm|yarn|bun)            echo "package.json" ;;
    uv|poetry|pip|pip3)           echo "pyproject.toml" ;;
    cargo|rustc)                  echo "Cargo.toml" ;;
    go)                           echo "go.mod" ;;
    bundle|gem)                   echo "Gemfile" ;;
    mvn)                          echo "pom.xml" ;;
    gradle|./gradlew)             echo "build.gradle" ;;
    *)                            echo "" ;;
  esac
}

REPORT=""
for entry in "${CHECKS[@]}"; do
  label="${entry%%|*}"
  cmd="${entry#*|}"

  # Skip empty (user opted out of this check during intake).
  [ -z "$cmd" ] && continue

  # Skip if the first binary in the command isn't on PATH.
  first="$(printf '%s' "$cmd" | awk '{print $1}')"
  if ! command -v "$first" >/dev/null 2>&1; then continue; fi

  # Skip if the stack manifest hasn't landed yet. Project-relative path —
  # the cd above pins us to CLAUDE_PROJECT_DIR.
  manifest="$(manifest_for "$first")"
  if [ -n "$manifest" ] && [ ! -f "$manifest" ]; then continue; fi

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
