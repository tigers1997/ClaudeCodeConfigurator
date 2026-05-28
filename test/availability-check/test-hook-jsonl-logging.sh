#!/usr/bin/env bash
# Hook writes JSONL log if .claude/logs/ exists in CWD (or via env override).
set -euo pipefail
HOOK="$PWD/templates/safety/hooks/check-package-availability.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH"; exit 0
fi

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT
mkdir -p "$tmp/.claude/logs"

# Allow case (silent stderr, but should still log)
input='{"tool_name":"Bash","tool_input":{"command":"apt install bash"}}'
(cd "$tmp" && printf '%s' "$input" | bash "$HOOK") 2>/dev/null

log_file="$tmp/.claude/logs/availability-check.log"
[ -f "$log_file" ] || { echo "FAIL: log file not created"; exit 1; }
grep -q '"decision":"allow"' "$log_file" || { echo "FAIL: allow decision not logged"; cat "$log_file"; exit 1; }
grep -q '"pm":"apt"' "$log_file" || { echo "FAIL: pm not logged"; exit 1; }

# Deny case
input='{"tool_name":"Bash","tool_input":{"command":"apt install definitely-not-real-xyz123"}}'
(cd "$tmp" && printf '%s' "$input" | bash "$HOOK") 2>/dev/null || true
grep -q '"decision":"deny"' "$log_file" || { echo "FAIL: deny decision not logged"; cat "$log_file"; exit 1; }

# Without logs dir, no file should be created.
tmp2=$(mktemp -d)
input='{"tool_name":"Bash","tool_input":{"command":"apt install bash"}}'
(cd "$tmp2" && printf '%s' "$input" | bash "$HOOK") 2>/dev/null
[ ! -f "$tmp2/.claude/logs/availability-check.log" ] || { echo "FAIL: log file created when .claude/logs/ absent"; exit 1; }
rm -rf "$tmp2"

echo "PASS: JSONL logging works conditionally on .claude/logs/ presence"
