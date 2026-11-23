#!/usr/bin/env bash
# The scaffolded scripts/validate.sh against the REAL tools, on the committed
# fixtures. Each section runs only if its tool is installed and says SKIP
# otherwise, so on a bare machine this proves nothing and says so; on CI (which
# installs .NET 10, Node and pac) it proves the wrapper against what the tools
# actually print.
#
# Two limits are PINNED as passing on purpose: broken DAX and circular measures.
# They are what no offline check catches (docs/microsoft-data-stack.md). If a
# future TOM release starts catching them, these assertions fail, and the docs,
# the rule files and the review checklist need updating, not this test hacked.
# `A && B || fail` is the assertion idiom in this file: the fail branch is meant to run when either side is false.
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=test/stack-microsoft-data/_common.sh
. test/stack-microsoft-data/_common.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="$tmp/base"
scaffold "$base"; with_fixtures "$base"; git_init "$base"
ran=""; skipped=""

# vcheck TIER NAME MUTATION... : copy the project, apply a python mutation, run one tier -> sets $rc/$out
newproj() { rm -rf "$tmp/p"; cp -r "$base" "$tmp/p"; }
vt() { rc=0; out="$(cd "$tmp/p" && ./scripts/validate.sh "$@" 2>&1)" || rc=$?; }
skip_if_skipped() { # <tier> ; true (and records) when validate.sh could not run the tool
    if echo "$out" | grep -q "^\[validate\] $1 *SKIP"; then skipped="$skipped $1"; echo "  SKIP $1: $(echo "$out" | head -1 | cut -c1-140)"; return 0; fi
    return 1
}
edit() { python3 - "$tmp/p/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
assert old in t, f"{old!r} not in {p}"
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}
T=fabric/Sales.SemanticModel/definition/tables/Sales.tmdl

# ---------------------------------------------------------------- models (TOM, .NET 10)
newproj; vt models
if ! skip_if_skipped models; then
    [ "$rc" = 0 ] && echo "$out" | grep -q 'models    OK' || { echo "FAIL: the good model did not parse"; echo "$out"; exit 1; }
    # what it catches, with the parser's own file and line
    newproj; edit "$T" $'\t\tdataType: double' $'\t\t\tdataType: double'; vt models
    [ "$rc" = 1 ] && echo "$out" | grep -q 'TmdlFormatException' && echo "$out" | grep -q 'Line Number - 8' || { echo "FAIL: bad indentation not caught with its line"; echo "$out"; exit 1; }
    newproj; edit "$T" $'\t\tsummarizeBy: sum' $'\t\tsummarizeBy: sum\n\t\tbogusProperty: 1'; vt models
    [ "$rc" = 1 ] && echo "$out" | grep -q 'UnknownKeyword' || { echo "FAIL: an unknown keyword was not caught"; echo "$out"; exit 1; }
    newproj; edit fabric/Sales.SemanticModel/definition/relationships.tmdl "Date.DateKey" "Date.NoSuchColumn"; vt models
    [ "$rc" = 1 ] && echo "$out" | grep -q 'refers to an object which cannot be found' || { echo "FAIL: a relationship to a missing column was not caught"; echo "$out"; exit 1; }
    newproj; rm "$tmp/p/fabric/Sales.SemanticModel/definition/tables/Date.tmdl"; vt models
    [ "$rc" = 1 ] || { echo "FAIL: a ref table with no file was not caught"; echo "$out"; exit 1; }
    newproj; edit "$T" $'\tcolumn Amount' $'\tmeasure \'Total Sales\' = 1\n\n\tcolumn Amount'; vt models
    [ "$rc" = 1 ] && echo "$out" | grep -q 'TmdlSerializationException' || { echo "FAIL: a duplicate measure was not caught"; echo "$out"; exit 1; }
    # what it does NOT catch: pinned (see the header)
    newproj; edit "$T" "SUM(Sales[Amount])" "SUM(NoSuchTable[Nope]) + UNDEFINED_FUNCTION(1"; vt models
    [ "$rc" = 0 ] || { echo "FAIL: broken DAX is now caught offline. Update docs/microsoft-data-stack.md, the rules and the review checklist, then this test."; echo "$out"; exit 1; }
    newproj; edit "$T" $'\tcolumn Amount' $'\tmeasure A = [B] + 1\n\n\tmeasure B = [A] + 1\n\n\tcolumn Amount'; vt models
    [ "$rc" = 0 ] || { echo "FAIL: circular measures are now caught offline. Update the docs, rules and checklist, then this test."; echo "$out"; exit 1; }
    # the line endings and indentation styles Windows and editors produce still parse
    newproj; find "$tmp/p/fabric/Sales.SemanticModel/definition" -name '*.tmdl' -exec sed -i 's/$/\r/' {} +; vt models
    [ "$rc" = 0 ] || { echo "FAIL: CRLF TMDL no longer parses"; echo "$out"; exit 1; }
    newproj; sed -i 's/\t/    /g' "$tmp/p/fabric/Sales.SemanticModel/definition/tables/Date.tmdl"; vt models
    [ "$rc" = 0 ] || { echo "FAIL: space-indented TMDL no longer parses (the rules say consistent spaces are accepted)"; echo "$out"; exit 1; }
    ran="$ran models"
fi

# ---------------------------------------------------------------- report (PBIR, Node 20+)
newproj; vt report
if ! skip_if_skipped report; then
    [ "$rc" = 0 ] && echo "$out" | grep -q 'report    OK' || { echo "FAIL: the good report did not validate"; echo "$out"; exit 1; }
    newproj; rm "$tmp/p/fabric/Sales.Report/definition/version.json"; vt report
    [ "$rc" = 1 ] && echo "$out" | grep -q 'PBIR_VERSION_MISSING' || { echo "FAIL: a missing version.json was not caught"; echo "$out"; exit 1; }
    newproj; edit fabric/Sales.Report/definition/pages/page1/page.json '"FitToPage"' '"NotARealOption"'; vt report
    [ "$rc" = 1 ] && echo "$out" | grep -q 'PBIR_SCHEMA_VALIDATION_ERROR' || { echo "FAIL: a schema violation was not caught"; echo "$out"; exit 1; }
    newproj; edit fabric/Sales.Report/definition/pages/pages.json '"page1"' '"page1", "ghost"'; vt report
    [ "$rc" = 1 ] && echo "$out" | grep -q 'PBIR_PAGE_JSON_MISSING' || { echo "FAIL: a pageOrder naming a missing page was not caught"; echo "$out"; exit 1; }
    newproj; printf '\xef\xbb\xbf' | cat - "$tmp/p/fabric/Sales.Report/definition/version.json" > "$tmp/x" && mv "$tmp/x" "$tmp/p/fabric/Sales.Report/definition/version.json"; vt report
    [ "$rc" = 1 ] && echo "$out" | grep -q 'PBIR_JSON_PARSE_ERROR' || { echo "FAIL: a UTF-8 BOM was not caught"; echo "$out"; exit 1; }
    echo "$out" | grep -q "fabric/Sales.Report/definition/version.json" && ! echo "$out" | grep -q "$tmp" || { echo "FAIL: paths are not repo-relative"; echo "$out"; exit 1; }
    ran="$ran report"
fi

# ---------------------------------------------------------------- solution (pac)
newproj; vt solution
if ! skip_if_skipped solution; then
    [ "$rc" = 0 ] && echo "$out" | grep -q 'solution  OK' || { echo "FAIL: the good solution did not pack"; echo "$out"; exit 1; }
    # THE TRAP, against the real tool: pac exits 0 and prints no "warning"
    newproj; edit power-platform/MySolution/Other/Solution.xml "<RootComponents />" '<RootComponents><RootComponent type="61" schemaName="myp_/js/app.js" behavior="0" /></RootComponents>'; vt solution
    [ "$rc" = 1 ] && echo "$out" | grep -q 'pac exited 0 but reported a problem' && echo "$out" | grep -q 'not defined in customizations' \
        || { echo "FAIL: pac's exit-0 'root components are not defined' case was not turned into a failure"; echo "$out"; exit 1; }
    newproj; printf '<ImportExportXml><Entities></ImportExportXml>' > "$tmp/p/power-platform/MySolution/Other/Customizations.xml"; vt solution
    [ "$rc" = 1 ] && echo "$out" | grep -q 'pac exited 1' && echo "$out" | grep -q 'start tag' || { echo "FAIL: malformed XML was not caught"; echo "$out"; exit 1; }
    ran="$ran solution"
fi

# CI sets REQUIRE_REAL_TOOLS=1: a runner that lost a tool must fail, not pass on nothing.
if [ -n "${REQUIRE_REAL_TOOLS:-}" ] && [ -n "$skipped" ]; then
    echo "FAIL: REQUIRE_REAL_TOOLS is set, but these tiers could not run:$skipped"; exit 1
fi
echo "PASS: real tools exercised for:${ran:- (none)}${skipped:+ ; skipped:$skipped}"
[ -n "$ran" ] || echo "NOTE: no tool was installed, so this run proved nothing about the real tools"
