#!/usr/bin/env bash
# microbit-enforcer: PreToolUse hook for /freeze, /guard, /careful microbits.
#
# Reads the tool-call payload from stdin (Claude Code PreToolUse contract).
# Exits 0 to allow the call; exits 2 to block. Exit 2 is the only non-zero
# code Claude Code treats as a block — exit 1 is a "non-blocking error": the
# message shows in the transcript and the edit lands anyway (hooks reference,
# "Other exit codes"). Earlier releases of this hook exited 1, so /freeze and
# /guard were advisory.
# Emits the documented PreToolUse decision JSON with permissionDecision "ask"
# for /careful matches so Claude Code surfaces a confirmation prompt.
#
# Marker files (project-local, session-scoped):
#   .claude/.frozen     — present  ⇒ block ALL Write/Edit/NotebookEdit
#   .claude/.guarded    — newline-separated globs; block on match
#   .claude/.careful    — newline-separated globs; prompt before match
#
# Lifecycle: a SessionStart hook (registered alongside this hook by the
# configurator's settings-patch, matcher startup|clear) clears all three
# files on a fresh session or /clear. Markers are session-scoped but
# survive --resume, compaction and /fork, so a long session keeps its markers.

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
    exit 2
fi

# 2. Guarded check (block on match).
if [[ -f "$GUARDED_FILE" && -n "$TARGET_PATH" ]]; then
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        shopt -s extglob globstar nullglob
        # shellcheck disable=SC2053
        if [[ "$TARGET_PATH" == $pattern ]]; then
            echo "[ GUARDED ] $TARGET_PATH matches '$pattern' — edit blocked." >&2
            exit 2
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
            # The documented PreToolUse decision shape (hooks reference,
            # "Decision control"); a bare {"action": "ask"} object is only
            # meaningful to Elicitation hooks and never produced a prompt here.
            # Built with json.dumps so a quote or backslash in the path cannot
            # produce malformed JSON.
            TARGET_PATH="$TARGET_PATH" PATTERN="$pattern" python3 -c '
import json, os
reason = "About to write %s (matches careful pattern %s). Proceed?" % (
    os.environ["TARGET_PATH"], os.environ["PATTERN"])
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": reason}}))
'
            exit 0
        fi
    done < "$CAREFUL_FILE"
fi

# Default: allow.
exit 0
