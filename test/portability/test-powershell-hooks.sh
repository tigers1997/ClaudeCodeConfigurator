#!/usr/bin/env bash
# --hook-shell powershell must produce hooks that actually run on a default
# Windows box, and a settings.json whose every entry points at an installed
# file with the right shell.
#
# The .ps1 hooks exist for Windows machines with no Git Bash, where
# `shell: "bash"` has nothing to resolve to. Two Windows-specific traps this
# guards against, both found by running it:
#   * Windows ships execution policy Restricted, so naming a .ps1 directly
#     fails with "running scripts is disabled on this system". The command
#     spawns PowerShell with -ExecutionPolicy Bypass instead.
#   * A wrapping `powershell -Command` collapses a non-zero child exit to 1,
#     which would turn a PreToolUse BLOCK (exit 2) into a non-blocking error.
#     The command ends with `; exit $LASTEXITCODE` to preserve it.
#
# Execution probes skip cleanly when no PowerShell is on PATH (pwsh ships on
# all three GitHub runner images; a developer machine may not have it).
set -euo pipefail

PS=""
for candidate in pwsh powershell.exe powershell; do
    if command -v "$candidate" >/dev/null 2>&1; then PS="$candidate"; break; fi
done

tmp=$(mktemp -d)
tmp2=$(mktemp -d)
trap 'rm -rf "$tmp" "$tmp2"' EXIT

# --- wiring -----------------------------------------------------------------
python3 configure.py --persona solo-experienced --yes --hook-shell powershell --dir "$tmp" >/dev/null

python3 - "$tmp" <<'PY'
import json, re, sys
from pathlib import Path

target = Path(sys.argv[1])
hooks = target / ".claude" / "hooks"
settings = json.loads((target / ".claude" / "settings.json").read_text(encoding="utf-8"))

missing, ps1_entries, sh_entries = [], 0, 0
for event, groups in settings.get("hooks", {}).items():
    for group in groups:
        for h in group.get("hooks", []):
            cmd, shell = h.get("command", ""), h.get("shell")
            if ".ps1" in cmd:
                ps1_entries += 1
                if shell != "powershell":
                    sys.exit(f"FAIL: {event} runs a .ps1 with shell={shell!r}")
                if "-ExecutionPolicy Bypass" not in cmd:
                    sys.exit(f"FAIL: {event} .ps1 command lacks the execution-policy "
                             f"bypass; it would fail on a default Windows box: {cmd}")
                if not cmd.rstrip().endswith("exit $LASTEXITCODE"):
                    sys.exit(f"FAIL: {event} .ps1 command does not propagate the exit "
                             f"code, so a hook BLOCK (exit 2) collapses to 1: {cmd}")
                m = re.search(r"hooks\\([\w.-]+\.ps1)", cmd)
                if not m:
                    sys.exit(f"FAIL: cannot find the hook filename in: {cmd}")
                if not (hooks / m.group(1)).exists():
                    missing.append((event, m.group(1)))
            elif cmd.endswith(".sh"):
                sh_entries += 1
                if shell != "bash":
                    sys.exit(f"FAIL: {event} runs a .sh with shell={shell!r}")
                if not (hooks / cmd.rsplit("/", 1)[-1]).exists():
                    missing.append((event, cmd.rsplit("/", 1)[-1]))

if missing:
    sys.exit(f"FAIL: settings reference hook files that were never installed: {missing}")
if ps1_entries == 0:
    sys.exit("FAIL: --hook-shell powershell produced no .ps1 hook entries")
# The point of the per-entry design: hooks with no .ps1 sibling stay bash.
if sh_entries == 0:
    sys.exit("FAIL: expected some hooks to remain bash (no .ps1 sibling)")

# The inline SessionStart marker-clear is not a script; it must have been
# translated, because `rm -f ... || true` is not valid PowerShell.
inline = [h.get("command", "")
          for g in settings["hooks"].get("SessionStart", [])
          for h in g.get("hooks", [])
          if "rm -f" in h.get("command", "")]
if inline:
    sys.exit(f"FAIL: a bash inline command survived the powershell swap: {inline}")

print(f"  wiring OK: {ps1_entries} powershell entries, {sh_entries} bash entries, none dangling")
PY

# --- the default must stay bash ---------------------------------------------
python3 configure.py --persona solo-experienced --yes --dir "$tmp2" >/dev/null
if ls "$tmp2/.claude/hooks/" | grep -q '\.ps1$'; then
    echo "FAIL: default scaffold installed PowerShell hooks"
    exit 1
fi
echo "  default scaffold is still bash-only"

if [ -z "$PS" ]; then
    echo "PASS (wiring only): no PowerShell on PATH, skipped execution probes"
    exit 0
fi

# --- behavior ---------------------------------------------------------------
# Under Git Bash, a Windows PowerShell cannot resolve /c/Users/... paths;
# cygpath is absent on the Linux/macOS runners, where paths are already native.
winpath() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}
run_hook() {  # $1=hook path  $2=stdin json ; echoes exit code
    printf '%s' "$2" | "$PS" -NoProfile -ExecutionPolicy Bypass \
        -File "$(winpath "$1")" >/dev/null 2>&1
    echo $?
}
expect() {  # $1=label $2=actual $3=want
    [ "$2" = "$3" ] || { echo "FAIL: $1 (exit $2, want $3)"; exit 1; }
}

block="$tmp/.claude/hooks/block-dangerous-bash.ps1"
expect "safe command allowed"      "$(run_hook "$block" '{"tool_input":{"command":"git status"}}')" 0
expect "dangerous command blocked" "$(run_hook "$block" '{"tool_input":{"command":"sudo rm -rf /"}}')" 2
expect "empty stdin allowed"       "$(run_hook "$block" '')" 0
expect "malformed stdin allowed"   "$(run_hook "$block" 'not json')" 0

secrets="$tmp/.claude/hooks/scan-secrets.ps1"
expect "clean content allowed" "$(run_hook "$secrets" '{"tool_input":{"file_path":"a.py","content":"x = 1"}}')" 0
expect "AWS key blocked"       "$(run_hook "$secrets" '{"tool_input":{"file_path":"a.py","content":"AKIAIOSFODNN7EXAMPLE"}}')" 2
expect "write to .env blocked" "$(run_hook "$secrets" '{"tool_input":{"file_path":"config/.env","content":"x"}}')" 2

enforcer="$tmp/.claude/hooks/microbit-enforcer.ps1"
export CLAUDE_PROJECT_DIR="$(winpath "$tmp")"
expect "unmarked write allowed" "$(run_hook "$enforcer" '{"tool_name":"Write","tool_input":{"file_path":"a.py"}}')" 0
expect "non-write tool ignored" "$(run_hook "$enforcer" '{"tool_name":"Bash","tool_input":{"command":"ls"}}')" 0
: > "$tmp/.claude/.frozen"
frozen_rc="$(run_hook "$enforcer" '{"tool_name":"Write","tool_input":{"file_path":"a.py"}}')"
rm -f "$tmp/.claude/.frozen"
expect "frozen marker blocks" "$frozen_rc" 1
unset CLAUDE_PROJECT_DIR

echo "PASS: powershell hooks wired per-entry, installed, and behaving ($PS)"
