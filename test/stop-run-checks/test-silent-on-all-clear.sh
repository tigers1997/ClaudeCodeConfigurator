#!/usr/bin/env bash
# A fully-passing check run must emit NOTHING. A run with any failure must
# still emit the full report — including the OK lines, which are useful
# context next to the failure.
#
# The generated Stop hook used to emit hookSpecificOutput.additionalContext
# on every run, pass or fail. "everything passed" is not actionable, so that
# spent context on every single stop for no signal. Reported downstream after
# a scaffolded project saw its all-clear runs feeding "lint: OK" back every
# turn.
#
# Both shells share the gate (ANY_FAIL / $anyFail) and are asserted the same
# way. PowerShell probes skip cleanly when no PowerShell is on PATH.
set -euo pipefail

PS=""
for candidate in pwsh powershell.exe powershell; do
    if command -v "$candidate" >/dev/null 2>&1; then PS="$candidate"; break; fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 configure.py --persona solo-experienced --yes --save-config-only "$tmp/cfg.json" >/dev/null

# Render a project whose lint check is $1 and whose other checks are blanked.
render() {
    local lint="$1" dest="$2"
    shift 2
    LINT="$lint" python3 - "$tmp/cfg.json" "$tmp/case.json" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
fv = cfg["formValues"]
fv["cmd_typecheck"] = ""
fv["cmd_test"] = ""
fv["cmd_lint"] = os.environ["LINT"]
json.dump(cfg, open(sys.argv[2], "w", encoding="utf-8"), indent=1)
PY
    mkdir -p "$dest"
    python3 configure.py --config "$tmp/case.json" --yes --dir "$dest" "$@" >/dev/null
}

# --- bash: all-clear must be silent -----------------------------------------
green="$tmp/green"
render 'python3 -c pass' "$green"
out=$(cd "$green" && echo '{}' | bash .claude/hooks/stop-run-checks.sh); status=$?
if [ "$status" -ne 0 ]; then
    echo "FAIL: all-clear run exited $status, expected 0"; exit 1
fi
if [ -n "$out" ]; then
    echo "FAIL: all-clear run emitted output, expected silence:"
    printf '%s\n' "$out"
    exit 1
fi
echo "  bash OK: all-clear run is silent (exit 0, no stdout)"

# --- bash: a failure must still report --------------------------------------
red="$tmp/red"
render 'sh -c "echo boom-detail; exit 3"' "$red"
out=$(cd "$red" && echo '{}' | bash .claude/hooks/stop-run-checks.sh); status=$?
if [ "$status" -ne 0 ]; then
    echo "FAIL: failing run exited $status, expected 0 (hook must never block)"; exit 1
fi
printf '%s' "$out" | grep -q 'hookSpecificOutput' \
    || { echo "FAIL: failing run emitted no report:"; printf '%s\n' "$out"; exit 1; }
printf '%s' "$out" | grep -q 'lint: FAIL (exit 3)' \
    || { echo "FAIL: report missing the FAIL line:"; printf '%s\n' "$out"; exit 1; }
printf '%s' "$out" | grep -q 'boom-detail' \
    || { echo "FAIL: report dropped the command's output:"; printf '%s\n' "$out"; exit 1; }
echo "  bash OK: failure still reports (FAIL line + command output)"

# --- bash: passing lines ride along with a failure --------------------------
mixed="$tmp/mixed"
MIXED_TC='python3 -c pass' python3 - "$tmp/cfg.json" "$tmp/case.json" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
fv = cfg["formValues"]
fv["cmd_typecheck"] = os.environ["MIXED_TC"]          # passes
fv["cmd_lint"] = 'sh -c "exit 4"'                     # fails
fv["cmd_test"] = ""
json.dump(cfg, open(sys.argv[2], "w", encoding="utf-8"), indent=1)
PY
mkdir -p "$mixed"
python3 configure.py --config "$tmp/case.json" --yes --dir "$mixed" >/dev/null
out=$(cd "$mixed" && echo '{}' | bash .claude/hooks/stop-run-checks.sh)
printf '%s' "$out" | grep -q 'typecheck: OK' \
    || { echo "FAIL: passing lines dropped from a report that has a failure:"; printf '%s\n' "$out"; exit 1; }
echo "  bash OK: passing lines ride along with the failure"

# --- powershell -------------------------------------------------------------
psgreen="$tmp/psgreen"
render 'python3 -c pass' "$psgreen" --hook-shell powershell
psred="$tmp/psred"
render 'python3 -c "raise SystemExit(3)"' "$psred" --hook-shell powershell

if [ -z "$PS" ]; then
    echo "  SKIP: no PowerShell on PATH; .ps1 behavior probes not run"
else
    run_ps() {
        local dir="$1" arg
        if command -v cygpath >/dev/null 2>&1; then arg=$(cygpath -w "$dir"); else arg="$dir"; fi
        "$PS" -NoProfile -ExecutionPolicy Bypass -Command \
            "\$env:CLAUDE_PROJECT_DIR='$arg'; '{}' | & '$arg\.claude\hooks\stop-run-checks.ps1'" 2>&1
    }
    out=$(run_ps "$psgreen" | tr -d '\r')
    if [ -n "$out" ]; then
        echo "FAIL: .ps1 all-clear run emitted output, expected silence:"
        printf '%s\n' "$out"; exit 1
    fi
    echo "  powershell OK ($PS): all-clear run is silent"

    out=$(run_ps "$psred" | tr -d '\r')
    printf '%s' "$out" | grep -q 'hookSpecificOutput' \
        || { echo "FAIL: .ps1 failing run emitted no report:"; printf '%s\n' "$out"; exit 1; }
    printf '%s' "$out" | grep -q 'lint: FAIL (exit 3)' \
        || { echo "FAIL: .ps1 report missing the FAIL line:"; printf '%s\n' "$out"; exit 1; }
    echo "  powershell OK ($PS): failure still reports"
fi

echo "PASS: Stop hook is silent on all-clear, loud on failure, in both shells"
