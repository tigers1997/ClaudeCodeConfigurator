#!/usr/bin/env bash
# Custom status line for Claude Code.
# Wire in settings.json: { "statusLine": { "type": "command", "command": "/absolute/path/to/statusline.sh" } }
#
# Receives a JSON blob on stdin with session info. Outputs a single line.
set -euo pipefail

INPUT="$(cat)"

MODEL="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("model",{}).get("display_name") or d.get("model",{}).get("id") or "?")' 2>/dev/null || echo "?")"
CWD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null || echo "")"
TOKENS="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;d=json.load(sys.stdin);c=d.get("usage",{}).get("context",{});print(c.get("used_pct","?"))' 2>/dev/null || echo "?")"
# 2.1.119+: effort.level and thinking.enabled may arrive on stdin.
# Empty string if absent — keeps older Claude Code versions unchanged.
EFFORT="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("effort",{}).get("level","") or "")' 2>/dev/null || echo "")"
THINKING="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;print("on" if json.load(sys.stdin).get("thinking",{}).get("enabled") else "")' 2>/dev/null || echo "")"

# Git branch + dirty marker
BRANCH=""
if [ -n "$CWD" ] && git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH="$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || echo 'detached')"
  if ! git -C "$CWD" diff --quiet 2>/dev/null || ! git -C "$CWD" diff --cached --quiet 2>/dev/null; then
    BRANCH="${BRANCH}*"
  fi
fi

DIR="$(basename "${CWD:-$(pwd)}")"

# ANSI colors
C_DIM="\033[2m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_GREEN="\033[32m"
C_RESET="\033[0m"

printf "${C_CYAN}%s${C_RESET} ${C_DIM}|${C_RESET} ${C_GREEN}%s${C_RESET} ${C_DIM}|${C_RESET} ${C_YELLOW}%s${C_RESET} ${C_DIM}|${C_RESET} ctx %s%%" \
  "$DIR" "${BRANCH:-no-git}" "$MODEL" "$TOKENS"

# Append effort/thinking indicators only when present.
if [ -n "$EFFORT" ]; then
  printf " ${C_DIM}|${C_RESET} effort %s" "$EFFORT"
fi
if [ -n "$THINKING" ]; then
  printf " ${C_DIM}|${C_RESET} ${C_YELLOW}think${C_RESET}"
fi
