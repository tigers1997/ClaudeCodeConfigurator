#!/usr/bin/env bash
# PreToolUse hook — blocks obviously dangerous Bash commands.
# Wire it in .claude/settings.json under hooks.PreToolUse with matcher: "Bash".
#
# Input (stdin): JSON with tool_input.command, plus session_id, cwd, etc.
# Output: exit 0 to allow; exit 2 to block (stderr is shown to Claude).
set -euo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"

# Deny list — extend as you find footguns.
PATTERNS=(
  'rm[[:space:]]+-rf?[[:space:]]+/($|[[:space:]])'     # rm -rf /
  'rm[[:space:]]+-rf?[[:space:]]+~($|[[:space:]])'     # rm -rf ~
  'rm[[:space:]]+-rf?[[:space:]]+\.($|[[:space:]])'    # rm -rf .
  'rm[[:space:]]+-rf?[[:space:]]+\*'                    # rm -rf *
  ':\(\)\{.*\|:&\};:'                                   # fork bomb
  '\bmkfs\b'                                            # format filesystem
  '\bdd[[:space:]]+.*of=/dev/'                          # dd to device
  '>\s*/dev/sda'                                        # overwrite disk
  '\bsudo[[:space:]]'                                   # sudo
  'curl[^|]+\|\s*(sh|bash|zsh)\b'                       # curl | sh
  'wget[^|]+\|\s*(sh|bash|zsh)\b'                       # wget | sh
  '\bchmod[[:space:]]+-R[[:space:]]+777\b'              # chmod -R 777
  '\bgit[[:space:]]+push[[:space:]]+.*--force\b'        # force push
  '\bgit[[:space:]]+reset[[:space:]]+--hard\b'          # hard reset
)

for pat in "${PATTERNS[@]}"; do
  if printf '%s' "$CMD" | grep -Eq "$pat"; then
    echo "[block-dangerous-bash] Blocked pattern: $pat" >&2
    echo "[block-dangerous-bash] Command: $CMD" >&2
    exit 2
  fi
done

exit 0
