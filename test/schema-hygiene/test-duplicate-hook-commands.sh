#!/usr/bin/env bash
# F3 (dogfood 2026-05-30): check_settings_validates must flag a hook command
# wired more than once under the SAME (event, matcher) — it fires multiple
# times per matching call. Belt-and-suspenders regression net for the F1
# symptom; catches render-time/template dups and stale pre-fix settings.json.
# The same command under DIFFERENT matchers is legitimate and must NOT flag.
set -euo pipefail

python3 - <<'EOF'
import sys
sys.path.insert(0, '.')
from configure import check_settings_validates, _find_duplicate_hook_commands

# --- The F1 symptom: same command in two groups that share matcher "Bash" ---
dup = {"hooks": {"PreToolUse": [
    {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "x/.claude/hooks/block-dangerous-bash.sh", "timeout": 10}]},
    {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "x/.claude/hooks/block-dangerous-bash.sh", "timeout": 10},
        {"type": "command", "command": "x/.claude/hooks/check-package-availability.sh", "timeout": 10}]},
]}}
found = _find_duplicate_hook_commands(dup)
assert any(ev == "PreToolUse" and m == "Bash" and "block-dangerous-bash" in cmd and n == 2
           for ev, m, cmd, n in found), f"helper missed same-matcher dup: {found}"
w = check_settings_validates(dup)
assert any("block-dangerous-bash" in msg and "PreToolUse" in msg and "Bash" in msg
           for msg in w), f"preflight missed dup: {w}"
# check-package-availability appears once -> not flagged (no false positive)
assert not any("check-package-availability" in cmd for ev, m, cmd, n in found), \
    f"false positive on singleton: {found}"

# --- Legitimate: same command under DIFFERENT matchers must NOT be flagged ---
cross = {"hooks": {"PreToolUse": [
    {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "x/log.sh", "timeout": 5}]},
    {"matcher": "Write|Edit", "hooks": [
        {"type": "command", "command": "x/log.sh", "timeout": 5}]},
]}}
assert _find_duplicate_hook_commands(cross) == [], \
    f"false positive on same-command-different-matcher: {_find_duplicate_hook_commands(cross)}"

# --- Within one group, the same command twice is also caught ---
within = {"hooks": {"PostToolUse": [
    {"matcher": "Write|Edit", "hooks": [
        {"type": "command", "command": "x/fmt.sh", "timeout": 5},
        {"type": "command", "command": "x/fmt.sh", "timeout": 5}]},
]}}
fw = _find_duplicate_hook_commands(within)
assert any(m == "Write|Edit" and "fmt.sh" in cmd and n == 2 for ev, m, cmd, n in fw), \
    f"missed within-group dup: {fw}"

# --- Clean: each command once per matcher -> no dup warning ---
clean = {"hooks": {"PreToolUse": [
    {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "x/block-dangerous-bash.sh", "timeout": 10},
        {"type": "command", "command": "x/check-package-availability.sh", "timeout": 10}]},
    {"matcher": "Write|Edit", "hooks": [
        {"type": "command", "command": "x/scan-secrets.sh", "timeout": 10}]},
]}}
assert _find_duplicate_hook_commands(clean) == [], \
    f"false positive on clean: {_find_duplicate_hook_commands(clean)}"

# --- No hooks key at all -> safe, empty ---
assert _find_duplicate_hook_commands({"$schema": "x"}) == []

print("PASS: same-matcher dup flagged; cross-matcher allowed; within-group caught; clean passes")
EOF
