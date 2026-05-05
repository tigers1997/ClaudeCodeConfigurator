#!/usr/bin/env bash
# slop-scan: PostToolUse hook on Write/Edit/NotebookEdit.
#
# Reads tool-call payload from stdin (Claude Code PostToolUse contract).
# Reads SLOP_SCAN_ACTION from env (default: warn).
# Reads SLOP_SCAN_DENSITY (default: 0) and SLOP_SCAN_IMPORTS (default: 0)
# from env to enable opt-in noisier patterns.
#
# Output:
#   warn mode  → [ SLOP ] block on stderr; exit 0 (write proceeds)
#   block mode → [ SLOP ] block on stderr; exit 1 (tool call rejected)
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
    echo "[ SLOP ]" >&2
    printf '%s' "$FINDINGS" >&2
    if [[ "$ACTION" == "block" ]]; then
        exit 1
    fi
fi

exit 0
