#!/usr/bin/env bash
# microbit-enforcer: PreToolUse hook for /freeze, /guard, /careful microbits.
#
# Reads the tool-call payload from stdin (Claude Code PreToolUse contract).
# Exits 0 to allow the call; exits non-zero to block.
# Emits JSON `{"action":"ask",...}` to stdout for /careful matches so
# Claude Code surfaces a confirmation prompt to the user.
#
# Marker files (project-local, session-scoped):
#   .claude/.frozen     — present  ⇒ block ALL Write/Edit/NotebookEdit
#   .claude/.guarded    — newline-separated globs; block on match
#   .claude/.careful    — newline-separated globs; prompt before match
#
# Lifecycle: a SessionStart hook (registered alongside this hook by the
# configurator's settings-patch) clears all three files. Markers are
# session-scoped, not persistent.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
FROZEN_FILE="$PROJECT_DIR/.claude/.frozen"
GUARDED_FILE="$PROJECT_DIR/.claude/.guarded"
CAREFUL_FILE="$PROJECT_DIR/.claude/.careful"

PAYLOAD="$(cat)"

# Tool name is at a standard JSON path in the PreToolUse contract.
TOOL_NAME="$(echo "$PAYLOAD" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_name', ''))
except Exception:
    pass
" 2>/dev/null)"

# Only Write/Edit/NotebookEdit are gated. Others pass through.
case "$TOOL_NAME" in
    Write|Edit|NotebookEdit) ;;
    *) exit 0 ;;
esac

TARGET_PATH="$(echo "$PAYLOAD" | python3 -c "
import sys, json
try:
    p = json.load(sys.stdin)
    ti = p.get('tool_input', {})
    print(ti.get('file_path') or ti.get('notebook_path') or '')
except Exception:
    pass
" 2>/dev/null)"

# 1. Frozen check — overrides everything.
if [[ -f "$FROZEN_FILE" ]]; then
    echo "[ FROZEN ] Write/Edit/NotebookEdit blocked until /unfreeze." >&2
    exit 1
fi

# 2. Guarded check (block on match).
if [[ -f "$GUARDED_FILE" && -n "$TARGET_PATH" ]]; then
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        shopt -s extglob globstar nullglob
        # shellcheck disable=SC2053
        if [[ "$TARGET_PATH" == $pattern ]]; then
            echo "[ GUARDED ] $TARGET_PATH matches '$pattern' — edit blocked." >&2
            exit 1
        fi
    done < "$GUARDED_FILE"
fi

# 3. Careful check (prompt on match).
if [[ -f "$CAREFUL_FILE" && -n "$TARGET_PATH" ]]; then
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        shopt -s extglob globstar nullglob
        # shellcheck disable=SC2053
        if [[ "$TARGET_PATH" == $pattern ]]; then
            cat <<JSON
{"action": "ask", "question": "About to write '$TARGET_PATH' (matches careful pattern '$pattern'). Proceed?"}
JSON
            exit 0
        fi
    done < "$CAREFUL_FILE"
fi

# Default: allow.
exit 0
