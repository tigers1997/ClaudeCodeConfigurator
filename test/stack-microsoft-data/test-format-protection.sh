#!/usr/bin/env bash
# The shipped format-on-write hook runs prettier on *.json|*.yml|*.md and
# `ruff format` plus `ruff check --fix` on *.py, passing the file path directly.
# Left alone it would reformat Fabric notebooks and Microsoft-written sources.
# The stack ships ruff.toml and .prettierignore for that, and this proves they
# work: against the real tools, and the real hook script, when installed.
#
# Verified while building this: ruff IGNORES `extend-exclude` for a file passed on
# the command line unless `force-exclude = true`, which is why that line exists.
set -euo pipefail
. test/stack-microsoft-data/_common.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
p="$tmp/p"
scaffold "$p"; git_init "$p"
sha() { sha256sum "$1" | cut -c1-16; }

mkdir -p "$p/fabric/Etl.Notebook" "$p/fabric/Sales.Report/definition" "$p/power-platform/solutions/S" "$p/src"
cat > "$p/fabric/Etl.Notebook/notebook-content.py" <<'PY'
# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": { "name": "synapse_pyspark" }
# META }

# CELL ********************

import os,sys
x = {  'a':1 }
PY
cp "$p/fabric/Etl.Notebook/notebook-content.py" "$p/src/job.py"
printf '{"a":1,\n"b":[1,2,   3]}\n' > "$p/fabric/Sales.Report/definition/report.json"
printf "Publisher:\n  UniqueName:   'x'\n" > "$p/power-platform/solutions/S/solution.yml"
printf '{"a":1,\n"b":[1,2,   3]}\n' > "$p/docs-plain.json"

hook="$p/.claude/hooks/format-on-write.sh"
fire() { # run the REAL hook for one file, as Claude Code would (JSON on stdin, cwd = project)
    (cd "$p" && printf '{"tool_input":{"file_path":"%s"}}' "$p/$1" | CLAUDE_PROJECT_DIR="$p" bash "$hook" >/dev/null 2>&1) || true
}
ran=""

if command -v ruff >/dev/null 2>&1; then
    n0=$(sha "$p/fabric/Etl.Notebook/notebook-content.py"); j0=$(sha "$p/src/job.py")
    fire fabric/Etl.Notebook/notebook-content.py; fire src/job.py
    [ "$(sha "$p/fabric/Etl.Notebook/notebook-content.py")" = "$n0" ] \
        || { echo "FAIL: the format hook reformatted or auto-fixed a Fabric notebook (ruff.toml force-exclude is not working)"; exit 1; }
    [ "$(sha "$p/src/job.py")" != "$j0" ] \
        || { echo "FAIL: ordinary Python is no longer formatted: the exclusion is too broad"; exit 1; }
    grep -q 'x = {"a": 1}' "$p/src/job.py" || { echo "FAIL: ruff did not format src/job.py as expected"; exit 1; }
    # and the reason the line exists: without force-exclude the notebook IS reformatted
    printf 'extend-exclude = ["fabric/**/notebook-content.py"]\n' > "$p/ruff.toml"
    cp "$p/src/job.py" "$p/fabric/Etl.Notebook/notebook-content.py"; sed -i 's/x = {"a": 1}/x = {  "a":1 }/' "$p/fabric/Etl.Notebook/notebook-content.py"
    n1=$(sha "$p/fabric/Etl.Notebook/notebook-content.py"); fire fabric/Etl.Notebook/notebook-content.py
    [ "$(sha "$p/fabric/Etl.Notebook/notebook-content.py")" != "$n1" ] \
        || { echo "FAIL: ruff now honours extend-exclude for explicit files; force-exclude may no longer be needed (check the ruff.toml comment)"; exit 1; }
    cp "$(pwd)/templates/stack-microsoft-data/ruff.toml" "$p/ruff.toml"
    # The two Python helpers land in users' repos, where `ruff check .` (the Python tier) lints them
    # and the format hook rewrites anything unformatted: a first run must not fail on files the user
    # did not write. ruff 0.17's default rule set is much wider than the classic one.
    (cd "$p" && ruff check --isolated scripts/check_fabric_items.py scripts/report_diagnostics.py >/dev/null 2>&1) \
        || { echo "FAIL: the shipped helper scripts fail 'ruff check' with default settings"; exit 1; }
    (cd "$p" && ruff format --isolated --check scripts/check_fabric_items.py scripts/report_diagnostics.py >/dev/null 2>&1) \
        || { echo "FAIL: the shipped helper scripts are not ruff-formatted (the format hook would rewrite them)"; exit 1; }
    ran="$ran ruff"
else
    [ -z "${REQUIRE_REAL_TOOLS:-}" ] || { echo "FAIL: REQUIRE_REAL_TOOLS is set and ruff is not installed"; exit 1; }
    echo "  SKIP ruff: not installed"
fi

if command -v prettier >/dev/null 2>&1; then
    r0=$(sha "$p/fabric/Sales.Report/definition/report.json"); y0=$(sha "$p/power-platform/solutions/S/solution.yml"); d0=$(sha "$p/docs-plain.json")
    fire fabric/Sales.Report/definition/report.json; fire power-platform/solutions/S/solution.yml; fire docs-plain.json
    [ "$(sha "$p/fabric/Sales.Report/definition/report.json")" = "$r0" ] && [ "$(sha "$p/power-platform/solutions/S/solution.yml")" = "$y0" ] \
        || { echo "FAIL: prettier reformatted Fabric or Power Platform source (.prettierignore is not working)"; exit 1; }
    [ "$(sha "$p/docs-plain.json")" != "$d0" ] || { echo "FAIL: prettier no longer formats files outside fabric/ and power-platform/"; exit 1; }
    ran="$ran prettier"
else
    [ -z "${REQUIRE_REAL_TOOLS:-}" ] || { echo "FAIL: REQUIRE_REAL_TOOLS is set and prettier is not installed"; exit 1; }
    echo "  SKIP prettier: not installed"
fi

echo "PASS: the format hook leaves Fabric and Power Platform source alone; checked against:${ran:- (no formatter installed)}"
