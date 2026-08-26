#!/usr/bin/env bash
# cmd_* answers are interpolated into a quoted string literal in the generated
# Stop hook — a double-quoted bash array element, a single-quoted PowerShell
# hashtable value. Anything the host shell treats as syntax inside those quotes
# has to be escaped on the way in, or the literal ends early.
#
# The real-world break: a lint command with an embedded double quote, e.g.
#     python -c "import ast,io,glob; [ast.parse(io.open(f).read()) for f in glob.glob('*.py')]"
# rendered raw into `"lint|<cmd>"`, and the whole CHECKS array stopped parsing.
# The hook then failed at load with a syntax error and produced no report —
# the worst failure mode for a check loop, because it still looks installed.
# The quieter half of the same bug: a command with no parens splits into
# several array elements instead of erroring, and the check runs truncated.
#
# Both shells are asserted the same way: the file must parse, and each command
# must round-trip byte-for-byte out of the rendered literal.
#
# PowerShell probes skip cleanly when no PowerShell is on PATH (pwsh ships on
# all three GitHub runner images; a developer machine may not have it).
set -euo pipefail

PS=""
for candidate in pwsh powershell.exe powershell; do
    if command -v "$candidate" >/dev/null 2>&1; then PS="$candidate"; break; fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Every metacharacter that means something inside the target quoting context:
# double quote and single quote (the literal terminators), `$` and backtick
# (expansion/substitution in bash), backslash (escape in bash), and parens +
# semicolon (what turns a broken literal into a hard parse error).
LINT_CMD='python -c "import ast,io,glob; [ast.parse(io.open(f).read()) for f in glob.glob('"'"'*.py'"'"')]"'
TEST_CMD='sh -c "echo $HOME `id -u` \ done"'
TYPECHECK_CMD="mypy --config 'a b.ini' ."

python3 configure.py --persona solo-experienced --yes --save-config-only "$tmp/cfg.json" >/dev/null
LINT_CMD="$LINT_CMD" TEST_CMD="$TEST_CMD" TYPECHECK_CMD="$TYPECHECK_CMD" \
python3 - "$tmp/cfg.json" <<'PY'
import json, os, sys
path = sys.argv[1]
cfg = json.load(open(path, encoding="utf-8"))
cfg["formValues"]["cmd_lint"] = os.environ["LINT_CMD"]
cfg["formValues"]["cmd_test"] = os.environ["TEST_CMD"]
cfg["formValues"]["cmd_typecheck"] = os.environ["TYPECHECK_CMD"]
json.dump(cfg, open(path, "w", encoding="utf-8"), indent=1)
PY

# --- bash ------------------------------------------------------------------
bashdir="$tmp/bash"
mkdir -p "$bashdir"
python3 configure.py --config "$tmp/cfg.json" --yes --dir "$bashdir" >/dev/null

hook="$bashdir/.claude/hooks/stop-run-checks.sh"
[ -f "$hook" ] || { echo "FAIL: bash hook not scaffolded at $hook"; exit 1; }

if ! bash -n "$hook" 2>"$tmp/bash-syntax.err"; then
    echo "FAIL: rendered stop-run-checks.sh does not parse:"
    cat "$tmp/bash-syntax.err"
    exit 1
fi

# Source just the CHECKS array and print it back. Byte-exact round-trip is the
# assertion — escaping that mangles the command is no better than escaping that
# breaks the parse.
sed -n '/^CHECKS=(/,/^)/p' "$hook" > "$tmp/checks.sh"
bash -c 'set -u; . "$1"; printf "%s\n" "${CHECKS[@]}"' _ "$tmp/checks.sh" > "$tmp/checks.out"

{
    printf 'typecheck|%s\n' "$TYPECHECK_CMD"
    printf 'lint|%s\n' "$LINT_CMD"
    printf 'test|%s\n' "$TEST_CMD"
} > "$tmp/checks.expected"

if ! diff -u "$tmp/checks.expected" "$tmp/checks.out"; then
    echo "FAIL: CHECKS entries didn't round-trip (expected left, got right)"
    exit 1
fi
echo "  bash OK: CHECKS parses and all 3 commands round-trip byte-exact"

# The escaping must not leak into prose targets — CLAUDE.md renders the same
# answers inside Markdown backticks, where a bash backslash would be visible.
grep -qF -- "- Lint: \`$LINT_CMD\`" "$bashdir/CLAUDE.md" \
    || { echo "FAIL: CLAUDE.md got shell-escaped cmd_lint; escaping leaked out of .sh"; exit 1; }
echo "  bash OK: CLAUDE.md kept the raw command (escaping is per-extension)"

# --- powershell ------------------------------------------------------------
psdir="$tmp/ps"
mkdir -p "$psdir"
python3 configure.py --config "$tmp/cfg.json" --yes --hook-shell powershell --dir "$psdir" >/dev/null

pshook="$psdir/.claude/hooks/stop-run-checks.ps1"
[ -f "$pshook" ] || { echo "FAIL: powershell hook not scaffolded at $pshook"; exit 1; }

# A raw single quote survives only as ''. Cheap check that runs without pwsh.
if grep -q "config 'a b.ini'" "$pshook"; then
    echo "FAIL: single quotes in cmd_typecheck reached the .ps1 undoubled"
    exit 1
fi

if [ -z "$PS" ]; then
    echo "  SKIP: no PowerShell on PATH; .ps1 parse/round-trip probes not run"
else
    # The probe lives in a file rather than -Command: it needs single-quoted
    # regexes (PowerShell interpolates `$` inside double quotes), which don't
    # survive nesting inside the single-quoted bash argument.
    cat > "$tmp/probe.ps1" <<'PROBE'
$ErrorActionPreference = 'Stop'
$f = $args[0]
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
if ($errs.Count) {
    $errs | ForEach-Object { $_.Message } | Write-Host
    throw 'rendered stop-run-checks.ps1 does not parse'
}
# Re-evaluate the $checks literal in isolation and emit label|command.
$m = [regex]::Match((Get-Content $f -Raw), '(?s)\$checks = @\(.*?\n\)')
if (-not $m.Success) { throw 'could not locate the $checks block' }
$c = & ([scriptblock]::Create($m.Value + "`n`$checks"))
$c | ForEach-Object { '{0}|{1}' -f $_.label, $_.command }
PROBE

    # Git Bash hands out MSYS paths; PowerShell needs the Windows form.
    if command -v cygpath >/dev/null 2>&1; then
        probe_arg=$(cygpath -w "$tmp/probe.ps1"); hook_arg=$(cygpath -w "$pshook")
    else
        probe_arg="$tmp/probe.ps1"; hook_arg="$pshook"
    fi

    if ! "$PS" -NoProfile -ExecutionPolicy Bypass -File "$probe_arg" "$hook_arg" > "$tmp/ps.out" 2>&1; then
        echo "FAIL: powershell probe failed"
        cat "$tmp/ps.out"
        exit 1
    fi

    # PowerShell writes CRLF; --strip-trailing-cr keeps that from reading
    # as a round-trip failure (the expected file is LF).
    if ! diff -u --strip-trailing-cr "$tmp/checks.expected" "$tmp/ps.out"; then
        echo "FAIL: \$checks entries didn't round-trip (expected left, got right)"
        exit 1
    fi
    echo "  powershell OK ($PS): \$checks parses and all 3 commands round-trip byte-exact"
fi

echo "PASS: cmd_* answers survive interpolation into both generated Stop hooks"
