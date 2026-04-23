#!/usr/bin/env bash
# PreCompact hook — writes a summary of the session before compaction
# so you have a durable record of what was done even after compression.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOG_DIR="$PROJECT_DIR/.claude/logs"
mkdir -p "$LOG_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$LOG_DIR/compact-$TS.md"

INPUT="$(cat)"
SESSION="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id",""))')"

{
  echo "# Pre-compact snapshot $TS"
  echo
  echo "session_id: $SESSION"
  echo
  echo "## Git status"
  git -C "$PROJECT_DIR" status --short 2>/dev/null || true
  echo
  echo "## Recent commits (this session window)"
  git -C "$PROJECT_DIR" log --since='6 hours ago' --oneline 2>/dev/null || true
  echo
  echo "## Files changed since HEAD"
  git -C "$PROJECT_DIR" diff --name-status 2>/dev/null || true
} > "$OUT"

# Emit minimal JSON — don't inject heavy context.
echo "{\"suppressOutput\": true}"
exit 0
