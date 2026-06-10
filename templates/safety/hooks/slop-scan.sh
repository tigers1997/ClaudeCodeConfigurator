#!/usr/bin/env bash
# slop-scan: PostToolUse hook on Write/Edit/NotebookEdit.
#
# Reads tool-call payload from stdin (Claude Code PostToolUse contract).
# Reads SLOP_SCAN_ACTION from env (default: warn).
# Reads SLOP_SCAN_DENSITY (default: 0) and SLOP_SCAN_IMPORTS (default: 0)
# from env to enable opt-in noisier patterns.
# Reads SLOP_SCAN_PING (default: 1) — set 0 to drop the desktop-notification
# ping from the output.
#
# Output (decision JSON on stdout, always exit 0 — docs/03 "Decision JSON"):
#   warn mode  → {"systemMessage": "[ SLOP ] …"} — the write stands; the
#                user sees the warning.
#   block mode → {"decision": "block", "reason": "[ SLOP ] …"} — the write
#                already happened (PostToolUse can't undo it); the findings
#                are fed back to Claude as the blocking reason so it fixes
#                them. (The pre-2026-06 exit-1 form was a non-blocking error
#                per the exit-code contract: Claude never saw the findings.)
#   Both modes add "terminalSequence": an OSC 9 desktop notification + BEL,
#   allowlisted hook output on CC 2.1.141+; older CC ignores the field.
#
# Default patterns are intentionally tight (Spec #2 Section 3 tightening) —
# high confidence, low FP rate. Comment density and hallucinated imports
# are opt-in.

set -euo pipefail

ACTION="${SLOP_SCAN_ACTION:-warn}"
DENSITY_ON="${SLOP_SCAN_DENSITY:-0}"
IMPORTS_ON="${SLOP_SCAN_IMPORTS:-0}"

PAYLOAD="$(cat)"

TOOL_NAME="$(echo "$PAYLOAD" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_name', ''))
except Exception:
    pass
" 2>/dev/null || echo '')"

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
" 2>/dev/null || echo '')"

CONTENT="$(echo "$PAYLOAD" | python3 -c "
import sys, json
try:
    p = json.load(sys.stdin)
    ti = p.get('tool_input', {})
    # Edit uses new_string; Write uses content; NotebookEdit uses new_source
    print(ti.get('new_string') or ti.get('content') or ti.get('new_source') or '')
except Exception:
    pass
" 2>/dev/null || echo '')"

if [[ -z "$CONTENT" ]]; then
    exit 0
fi

# Pattern definitions (regex, label) — tight defaults only.
declare -a FILLER_PATTERNS=(
    "It is important to note"
    "In essence"
    "Furthermore"
    "Moreover"
)
declare -a MARKETING_PATTERNS=(
    "seamless"
    "elegant"
    "comprehensive"
)
declare -a HEDGING_PATTERNS=(
    "might possibly"
    "perhaps consider"
    "you may want to"
)

FINDINGS=""

scan_pattern() {
    local label="$1"; shift
    for pat in "$@"; do
        while IFS=: read -r line_no line_content; do
            [[ -z "$line_no" ]] && continue
            excerpt=$(echo "$line_content" | head -c 60)
            FINDINGS+="$TARGET_PATH:$line_no — $label: \"$excerpt\""$'\n'
        done < <(echo "$CONTENT" | grep -in -E "$pat" || true)
    done
}

scan_pattern "filler" "${FILLER_PATTERNS[@]}"
scan_pattern "marketing-voice" "${MARKETING_PATTERNS[@]}"
scan_pattern "hedging" "${HEDGING_PATTERNS[@]}"

# Em-dash spam: ≥3 em-dashes in a single line (proxy for comment block)
while IFS=: read -r line_no line_content; do
    [[ -z "$line_no" ]] && continue
    excerpt=$(echo "$line_content" | head -c 60)
    FINDINGS+="$TARGET_PATH:$line_no — em-dash-spam: \"$excerpt\""$'\n'
done < <(echo "$CONTENT" | grep -n -E '—.*—.*—' || true)

# Opt-in: comment density (rough — comments >40% of lines)
if [[ "$DENSITY_ON" == "1" ]]; then
    total=$(echo "$CONTENT" | wc -l)
    comments=$(echo "$CONTENT" | grep -c -E '^\s*(#|//|/\*|\*)' || true)
    if [[ "$total" -gt 10 && "$comments" -gt 0 ]]; then
        pct=$((comments * 100 / total))
        if [[ "$pct" -gt 40 ]]; then
            FINDINGS+="$TARGET_PATH:1 — comment-density: $pct% (>40% threshold)"$'\n'
        fi
    fi
fi

# Opt-in: hallucinated imports (best-effort; no AST)
if [[ "$IMPORTS_ON" == "1" && -n "$TARGET_PATH" ]]; then
    project_root="${CLAUDE_PROJECT_DIR:-.}"
    while IFS=: read -r line_no _ import_name; do
        [[ -z "$import_name" ]] && continue
        sym=$(echo "$import_name" | awk '{print $1}' | tr -d '[:punct:]' | head -c 40)
        [[ -z "$sym" ]] && continue
        if ! grep -rq --exclude-dir=.git --exclude-dir=node_modules --exclude="$TARGET_PATH" "$sym" "$project_root" 2>/dev/null; then
            FINDINGS+="$TARGET_PATH:$line_no — hallucinated-import: \"$sym\""$'\n'
        fi
    done < <(echo "$CONTENT" | grep -nE '^(from |import )' || true)
fi

if [[ -n "$FINDINGS" ]]; then
    SEQ=""
    if [[ "${SLOP_SCAN_PING:-1}" != "0" ]]; then
        N=$(printf '%s' "$FINDINGS" | grep -c .)
        SEQ="$(printf '\033]9;[ SLOP ] %d finding(s)\007' "$N")"
    fi
    SLOP_MSG="[ SLOP ]"$'\n'"$FINDINGS" SLOP_SEQ="$SEQ" SLOP_MODE="$ACTION" python3 -c '
import json, os
msg = os.environ["SLOP_MSG"]
if os.environ["SLOP_MODE"] == "block":
    out = {"decision": "block", "reason": msg}
else:
    out = {"systemMessage": msg}
seq = os.environ["SLOP_SEQ"]
if seq:
    out["terminalSequence"] = seq
print(json.dumps(out))
'
fi

exit 0
