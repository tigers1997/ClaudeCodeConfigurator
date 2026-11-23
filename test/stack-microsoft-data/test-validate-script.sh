#!/usr/bin/env bash
# scripts/validate.sh against STUB tools, so the wrapper's logic is pinned on any
# machine: which tier runs when, SKIP versus FAIL versus --strict, how each tool
# is found, and the trap that matters most: `pac solution pack` exiting 0 while
# reporting missing components. The stubs print what the REAL tools printed in
# the 2026-11-23 runs (test-real-tools.sh checks them against the real binaries
# where those are installed).
#
# The PATH is hermetic: only the stubs and symlinks to the few core tools the
# script needs, so a dotnet, pac or node on this machine cannot leak in.
# `A && B || fail` is the assertion idiom in this file: the fail branch is meant to run when either side is false.
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=test/stack-microsoft-data/_common.sh
. test/stack-microsoft-data/_common.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"; core="$tmp/core"; impl="$tmp/impl"
mkdir -p "$bin" "$core" "$impl"
for t in git python3 awk sed grep find sort head tail tr cut dirname mktemp rm cat env bash uname wc xargs; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [ -n "$p" ] && ln -sf "$p" "$core/$t"
done

# ---- stubs ---------------------------------------------------------------------
cat > "$bin/dotnet" <<'STUB'
#!/usr/bin/env bash
echo "dotnet $*" >> "$STUB_LOG"
case "$1" in
  --version) echo "${STUB_DOTNET_VERSION:-10.0.404}"; exit 0 ;;
  tool)
    if [ "$2" = "run" ] && [ "$3" = "pac" ]; then
      [ "${STUB_PAC_LOCAL:-0}" = 1 ] || { echo "Could not find any local tool 'pac'" >&2; exit 1; }
      shift 3; exec "$STUB_IMPL/pac" "$@"
    fi
    exit 0 ;;
  run)
    shift; case "$1" in *tmdl-check.cs) shift 2 ;; esac     # drop the script and --
    case "${STUB_TMDL:-ok}" in
      ok)   for d in "$@"; do echo "OK    $d: 2 tables, 1 measures, 1 relationships"; done; exit 0 ;;
      fail) echo "FAIL  $1: TmdlFormatException: TMDL Format Error:"; echo "	Parsing error type - Indentation"; echo "	Line Number - 8"; exit 1 ;;
      none) echo "/x/tmdl-check.cs : error NU1301: Unable to load the service index for source https://api.nuget.org/v3/index.json"; exit 1 ;;
    esac ;;
esac
STUB
cat > "$impl/pac" <<'STUB'
#!/usr/bin/env bash
echo "pac $*" >> "$STUB_LOG"
[ "$1" = help ] && { echo "Microsoft PowerPlatform CLI"; echo "Version: 2.16.1+gf5bc887 (.NET 10.0.15)"; exit 0; }
folder=""; zip=""
while [ $# -gt 0 ]; do case "$1" in --folder) folder="$2"; shift 2 ;; --zipfile) zip="$2"; shift 2 ;; *) shift ;; esac; done
echo "Microsoft PowerPlatform CLI"; echo "Version: 2.16.1+gf5bc887 (.NET 10.0.15)"; echo; echo "Packing Solution..."; echo "Packing $folder to $zip"
case "${STUB_PAC:-clean}" in
  clean)     echo "Processing Component: Entities"; echo "Unmanaged Pack complete."; echo "Packed Solution."; : > "$zip"; exit 0 ;;
  undefined) echo "Processing Sharded Component Files"; echo "Following root components are not defined in customizations:"; echo "  Type='WebResource', Id (or schema name)='WebResource-myp_/js/app.js'."; echo "Unmanaged Pack complete."; echo "Packed Solution."; : > "$zip"; exit 0 ;;
  warning)   echo "Warning: component omitted"; echo "Packed Solution."; exit 0 ;;
  error)     echo "Error: The 'Entities' start tag on line 1 position 19 does not match the end tag of 'ImportExportXml'. Line 1, position 30."; exit 1 ;;
  pathword)  echo "Processing Component: ErrorLogs"; echo "Packed Solution."; : > "$zip"; exit 0 ;;   # a component NAME containing 'Error' is not trouble
esac
STUB
cat > "$impl/powerbi-report-author" <<'STUB'
#!/usr/bin/env bash
echo "powerbi-report-author $* (npm_config_ignore_scripts=${npm_config_ignore_scripts:-})" >> "$STUB_LOG"
case "${STUB_PBIR:-ok}" in
  ok)      echo '{"data":{"result":"succeeded","errorCount":0,"warningCount":0,"reportPath":"/x"}}'; exit 0 ;;
  fail)    echo '{"data":{"result":"failed","errorCount":1,"warningCount":0,"reportPath":"/x","diagnostics":{"PBIR_VERSION_MISSING":{"severity":"error","items":[{"message":"Missing: Sales.Report/definition/version.json"}]}}}}'; exit 1 ;;
  garbage) echo "npm ERR! code ENOTFOUND"; exit 1 ;;
esac
STUB
cat > "$bin/npx" <<'STUB'
#!/usr/bin/env bash
echo "npx $* (npm_config_ignore_scripts=${npm_config_ignore_scripts:-})" >> "$STUB_LOG"
[ "${STUB_NPX_FAILS:-0}" = 1 ] && { echo "npm ERR! network"; exit 1; }
while [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done; shift       # drop npx's own flags and the `--`
exec "$STUB_IMPL/powerbi-report-author" "$@"
STUB
# On PATH only as a thin wrapper, so a test can take it away and leave npx the only way to get the tool.
# single quotes on purpose: the wrapper must expand $STUB_IMPL when it runs, not now
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nexec "$STUB_IMPL/powerbi-report-author" "$@"\n' > "$bin/powerbi-report-author"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nexec "$STUB_IMPL/pac" "$@"\n' > "$bin/pac"
cat > "$bin/node" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "--version" ] && echo "${STUB_NODE_VERSION:-v22.1.0}"
STUB
cat > "$bin/uv" <<'STUB'
#!/usr/bin/env bash
echo "uv $*" >> "$STUB_LOG"
shift; [ "$1" = "--quiet" ] && shift
case "$1" in
  ruff)   [ "${STUB_RUFF:-0}" = 0 ] && exit 0; echo "src/job.py:1:1: F401 unused import"; exit 1 ;;
  pytest) echo "pytest ran"; exit "${STUB_PYTEST:-0}" ;;
esac
STUB
chmod +x "$bin"/* "$impl"/*
export STUB_DIR="$bin" STUB_IMPL="$impl" STUB_LOG="$tmp/log"

# ---- a project with fixtures, committed ------------------------------------------
proj="$tmp/proj"
scaffold "$proj"; with_fixtures "$proj"; git_init "$proj"
V=./scripts/validate.sh
FULL="$bin:$core"     # every stub on PATH
# vrun PATH args... : sets $out and $rc ; env STUB_* set by the caller are inherited
vrun() { local p="$1"; shift; rc=0; out="$(cd "$proj" && env PATH="$p" "$V" "$@" 2>&1)" || rc=$?; }
want() { # <description> <expected rc> <text that must appear> [text that must NOT appear]
    [ "$rc" = "$2" ] || { echo "FAIL: $1: exit $rc, wanted $2"; echo "$out"; exit 1; }
    echo "$out" | grep -qF -- "$3" || { echo "FAIL: $1: output lacks '$3'"; echo "$out"; exit 1; }
    if [ -n "${4:-}" ] && echo "$out" | grep -qF -- "$4"; then echo "FAIL: $1: output must not contain '$4'"; echo "$out"; exit 1; fi
}
logged() { grep -qF -- "$1" "$tmp/log"; }

# 1. everything present and clean: OK x4, exit 0, nothing to say about python (no Python in the repo)
: > "$tmp/log"
vrun "$FULL"
want "all tiers clean" 0 "[validate] solution  OK"
for tier in repo models report; do echo "$out" | grep -q "^\[validate\] $tier *OK" || { echo "FAIL: tier $tier not OK"; echo "$out"; exit 1; }; done
echo "$out" | grep -q 'python' && { echo "FAIL: the python tier spoke although the repo has no Python"; exit 1; }
echo "$out" | grep -q 'structure only; DAX and M are not checked' || { echo "FAIL: the models line must say what it does not check"; exit 1; }
logged "powerbi-report-author validate fabric/Sales.Report (npm_config_ignore_scripts=true)" || { echo "FAIL: PBIR validator run without install scripts disabled"; cat "$tmp/log"; exit 1; }
logged "pac solution pack --folder power-platform/MySolution --zipfile" || { echo "FAIL: pac was not asked to pack the pack root"; cat "$tmp/log"; exit 1; }
logged "--packagetype Unmanaged" || { echo "FAIL: pack must be Unmanaged"; exit 1; }
logged "dotnet run" && grep -q "tmdl-check.cs -- fabric/Sales.SemanticModel/definition" "$tmp/log" || { echo "FAIL: dotnet was not given the TMDL definition folder"; cat "$tmp/log"; exit 1; }

# 2. a TMDL failure shows the parser's detail; the other tiers still run
STUB_TMDL=fail vrun "$FULL"
want "TMDL failure" 1 "[validate] models    FAIL" ; echo "$out" | grep -q 'Line Number - 8' || { echo "FAIL: the parser's file/line detail was dropped"; exit 1; }
echo "$out" | grep -q '^\[validate\] solution *OK' || { echo "FAIL: a models failure stopped later tiers"; exit 1; }

# 3. THE TRAP: pac exits 0 but reports undefined components (no "warning" label)
STUB_PAC=undefined vrun "$FULL" solution
want "pac exit 0 with undefined components" 1 "[validate] solution  FAIL" ; echo "$out" | grep -q 'not defined in customizations' || { echo "FAIL: the pac message was not shown"; echo "$out"; exit 1; }
echo "$out" | grep -q 'pac exited 0 but reported a problem' || { echo "FAIL: the exit-0 case is not named"; exit 1; }
STUB_PAC=warning vrun "$FULL" solution;  want "pac warning" 1 "FAIL"
STUB_PAC=error   vrun "$FULL" solution;  want "pac error exit" 1 "pac exited 1"
echo "$out" | grep -q "start tag on line 1" || { echo "FAIL: the pac error text was dropped"; exit 1; }
STUB_PAC=pathword vrun "$FULL" solution; want "a component NAME containing 'Error' is not trouble" 0 "OK"
STUB_PAC=clean   vrun "$FULL" solution;  want "clean pack" 0 "OK"

# 4. PBIR: failure detail; a tool that never ran is a SKIP (FAIL under --strict), not a verdict
STUB_PBIR=fail vrun "$FULL" report
want "PBIR failure" 1 "[validate] report    FAIL"; echo "$out" | grep -q 'ERROR PBIR_VERSION_MISSING' || { echo "FAIL: PBIR diagnostic missing"; exit 1; }
STUB_PBIR=garbage vrun "$FULL" report;          want "PBIR tool did not run" 0 "SKIP"
STUB_PBIR=garbage vrun "$FULL" --strict report; want "PBIR tool did not run, strict" 1 "FAIL"
STUB_TMDL=none vrun "$FULL" models;             want "no verdict from tmdl-check" 0 "SKIP" "FAIL"
STUB_TMDL=none vrun "$FULL" --strict models;    want "no verdict from tmdl-check, strict" 1 "did not run"

# 5. tool resolution: installed binary preferred; npx fallback is pinned and scripts-off; npx needs Node 20+
: > "$tmp/log"; vrun "$FULL" report; want "installed validator" 0 "OK"
grep -q '^npx' "$tmp/log" && { echo "FAIL: npx was used although the validator is installed"; cat "$tmp/log"; exit 1; }
mv "$bin/powerbi-report-author" "$tmp/pra"                 # now only npx can supply it
: > "$tmp/log"; vrun "$FULL" report; want "npx fallback" 0 "OK"
grep -q -- '--package=@microsoft/powerbi-report-authoring-cli@0.5.0' "$tmp/log" || { echo "FAIL: npx fallback is not pinned to 0.5.0"; cat "$tmp/log"; exit 1; }
grep -q 'npm_config_ignore_scripts=true' "$tmp/log" || { echo "FAIL: npx fallback ran install scripts"; exit 1; }
grep -qE -- '--package=[^ ]*@latest' "$tmp/log" && { echo "FAIL: unpinned npx"; exit 1; }
STUB_NODE_VERSION=v18.20.0 vrun "$FULL" report; want "Node 18 is too old for the fetch" 0 "SKIP"
STUB_NPX_FAILS=1 vrun "$FULL" report;          want "npx offline" 0 "SKIP"
mv "$tmp/pra" "$bin/powerbi-report-author"

# 6. dotnet too old for file-based apps, absent, and pac only as the pinned local tool
STUB_DOTNET_VERSION=9.0.300 vrun "$FULL" models; want "SDK 9" 0 "too old"
vrun "$core" models;                             want "no dotnet" 0 "dotnet not found"
mv "$bin/pac" "$tmp/pac"
vrun "$FULL" solution;                           want "no pac, no local tool" 0 "pac not found"
echo "$out" | grep -q 'dotnet tool restore' || { echo "FAIL: the SKIP does not say how to get pac"; exit 1; }
: > "$tmp/log"; STUB_PAC_LOCAL=1 vrun "$FULL" solution
want "pac as the pinned local tool" 0 "OK"
mv "$tmp/pac" "$bin/pac"; grep -q 'dotnet tool run pac help' "$tmp/log" || { echo "FAIL: local tool was not probed"; cat "$tmp/log"; exit 1; }

# 7. --strict: any SKIP fails; none passes
vrun "$core" --strict;  want "strict with nothing installed" 1 "this is not a pass"
vrun "$core";           want "non-strict with nothing installed" 0 "[validate] repo      OK"
vrun "$FULL" --strict;  want "strict with everything installed" 0 "[validate] repo      OK" "SKIP"

# 8. --changed: silent when nothing changed; otherwise only the tiers whose files did
vrun "$FULL" --changed
[ "$rc" = 0 ] && [ -z "$out" ] || { echo "FAIL: --changed on a clean tree must be silent (rc=$rc)"; echo "$out"; exit 1; }
printf '\n' >> "$proj/fabric/Sales.SemanticModel/definition/tables/Date.tmdl"
vrun "$FULL" --changed;  want "touched a TMDL file" 0 "models"
echo "$out" | grep -q 'report'   && { echo "FAIL: a TMDL change re-ran the report tier"; exit 1; }
echo "$out" | grep -q 'solution' && { echo "FAIL: a TMDL change re-ran the solution tier"; exit 1; }
git -C "$proj" checkout -q -- .
echo "<!-- x -->" >> "$proj/power-platform/MySolution/Other/Customizations.xml"
vrun "$FULL" --changed;  want "touched a solution file" 0 "solution"
echo "$out" | grep -qE 'models|report' && { echo "FAIL: a solution change re-ran models or report"; exit 1; }
git -C "$proj" checkout -q -- .
cp -r "$proj/fabric/Sales.Report" "$proj/fabric/New.Report"                      # untracked: counts as changed
vrun "$FULL" --changed;  want "untracked new report" 1 "repo"                    # the copy shares the original's logicalId
git -C "$proj" clean -fdq

# 9. tiers on the command line, unknown arguments, help
vrun "$FULL" models;      want "one tier" 0 "models"; echo "$out" | grep -qE 'report|solution' && { echo "FAIL: asked for models, got more"; exit 1; }
vrun "$FULL" bogus;       want "unknown argument" 2 "unknown argument 'bogus'"
vrun "$FULL" --help;      want "help" 0 "headless validation for Fabric"

# 10. the python tier: only when the repo has Python; uv preferred; pytest exit 5 (nothing collected) is not a failure
mkdir -p "$proj/tests"; printf '[project]\nname = "x"\n' > "$proj/pyproject.toml"; : > "$tmp/log"
vrun "$FULL" python;      want "python via uv" 0 "python    OK   ruff, pytest"
grep -q 'uv run --quiet ruff check .' "$tmp/log" && grep -q 'uv run --quiet pytest -q' "$tmp/log" || { echo "FAIL: uv was not used for ruff and pytest"; cat "$tmp/log"; exit 1; }
STUB_RUFF=1 vrun "$FULL" python;    want "ruff failure" 1 "python    FAIL"
STUB_PYTEST=1 vrun "$FULL" python;  want "pytest failure" 1 "pytest"
STUB_PYTEST=5 vrun "$FULL" python;  want "pytest collected nothing" 0 "OK"
vrun "$core" python;                want "no python tooling" 0 "SKIP"
vrun "$core" --strict python;       want "no python tooling, strict" 1 "not a pass"
rm -rf "$proj/tests" "$proj/pyproject.toml"

# 11. a TMSL-only model (model.bim, no definition/) is not parsed, and not reported as parsed
rm -rf "$proj/fabric/Sales.SemanticModel/definition"; printf '{}' > "$proj/fabric/Sales.SemanticModel/model.bim"
vrun "$FULL" models;      ! echo "$out" | grep -qE 'models' || { echo "FAIL: a TMSL-only model was reported on"; echo "$out"; exit 1; }

echo "PASS: validate.sh picks tiers by change, finds its tools in the documented order, and fails on pac's exit-0 trap"
