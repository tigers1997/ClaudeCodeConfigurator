#!/usr/bin/env bash
# Adding the stack to a repository that already has ruff, prettier or dotnet-tool
# config. Three of the module's files are ones a repo often owns: ruff.toml,
# .prettierignore, .config/dotnet-tools.json. By default the user's copy is kept
# and the stack's is staged, so the lines the stack depends on can silently be
# missing (the format hook would then rewrite Fabric notebooks). A ruff.toml also
# outranks [tool.ruff] in pyproject.toml. configure.py must warn exactly when it
# matters, and stay quiet on a fresh target, on a re-run, and when the user's
# files already carry the lines.
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=test/stack-microsoft-data/_common.sh
. test/stack-microsoft-data/_common.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
T=templates/stack-microsoft-data

W_RUFF="ruff.toml already exists without the stack's lines"
W_DOTRUFF=".ruff.toml outranks ruff.toml"
W_PYPROJECT="pyproject.toml has a [tool.ruff] table"
W_PRETTIER=".prettierignore already exists without"
W_TOOLS=".config/dotnet-tools.json already exists without the pinned"
W_STEP="Merge the stack's lines into your existing ruff, prettier and dotnet tools"

run() { python3 configure.py --persona solo-experienced --yes --stack microsoft-data --dir "$1" 2>&1; }
want()    { echo "$out" | grep -qF -- "$2" || { echo "FAIL: $1: expected '$2'"; echo "$out" | sed -n '/MODULE WARNINGS/,/APPLIED/p' | head -20; exit 1; }; }
wantnot() { ! echo "$out" | grep -qF -- "$2" || { echo "FAIL: $1: did not expect '$2'"; exit 1; }; }
quiet() { # <description>: none of the stack-config warnings fired
    for w in "$W_RUFF" "$W_DOTRUFF" "$W_PYPROJECT" "$W_PRETTIER" "$W_TOOLS" "$W_STEP"; do wantnot "$1" "$w"; done
}

# 1. fresh target: silent
out=$(run "$tmp/fresh"); quiet "fresh target"

# 2. a re-run of a project this tool scaffolded: silent (its own files carry the lines)
out=$(run "$tmp/fresh"); quiet "re-run of a scaffolded project"

# 3. the user owns all three files and they lack what the stack needs
d="$tmp/owned"; mkdir -p "$d/.config"
printf 'line-length = 120\n' > "$d/ruff.toml"
printf 'node_modules/\n' > "$d/.prettierignore"
printf '{"version": 1, "isRoot": true, "tools": {"dotnet-ef": {"version": "9.0.0", "commands": ["dotnet-ef"]}}}\n' > "$d/.config/dotnet-tools.json"
out=$(run "$d")
want "user-owned files, ruff" "$W_RUFF"; want "user-owned files, prettier" "$W_PRETTIER"; want "user-owned files, tools" "$W_TOOLS"
want "next step" "$W_STEP"; wantnot "ruff.toml present, so no pyproject warning" "$W_PYPROJECT"
[ "$(cat "$d/ruff.toml")" = 'line-length = 120' ] || { echo "FAIL: the user's ruff.toml was changed"; exit 1; }
[ "$(cat "$d/.prettierignore")" = 'node_modules/' ] || { echo "FAIL: the user's .prettierignore was changed"; exit 1; }
grep -q dotnet-ef "$d/.config/dotnet-tools.json" && ! grep -q powerapps "$d/.config/dotnet-tools.json" || { echo "FAIL: the user's tools manifest was changed"; exit 1; }
for f in ruff.toml .prettierignore .config/dotnet-tools.json; do
    [ -f "$d/.claude-retrofit/incoming/$f" ] || { echo "FAIL: the stack's $f was not staged"; exit 1; }
done
grep -qF "$W_RUFF" "$d/.claude-retrofit/REPORT.md" && grep -qF "$W_TOOLS" "$d/.claude-retrofit/REPORT.md" \
    || { echo "FAIL: the retrofit report does not carry the stack's merge notes"; exit 1; }

# 4. the user's files already carry the lines (here: copies of the stack's own): silent
d="$tmp/carry"; mkdir -p "$d/.config"
cp "$T/ruff.toml" "$d/ruff.toml"; cp "$T/dot-prettierignore" "$d/.prettierignore"; cp "$T/dot-config/dotnet-tools.json" "$d/.config/dotnet-tools.json"
out=$(run "$d"); quiet "files that already carry the lines"
# ... also with their own extras around the lines, and with the pac key in another case
printf 'extend = "pyproject.toml"\nline-length = 100\nforce-exclude = true\nextend-exclude = ["fabric/**/notebook-content.py", "build"]\n' > "$d/ruff.toml"
printf '# mine\nfabric/\npower-platform/\ndist/\n' > "$d/.prettierignore"
printf '{"version":1,"isRoot":true,"tools":{"Microsoft.PowerApps.CLI.Tool":{"version":"2.0.0","commands":["pac"]}}}\n' > "$d/.config/dotnet-tools.json"
out=$(run "$d"); quiet "files with the lines among the user's own"

# 5. each file, one requirement short
d="$tmp/short"; mkdir -p "$d/.config"
printf 'force-exclude = true\n' > "$d/ruff.toml"                       # no notebook exclusion
printf 'fabric/\n' > "$d/.prettierignore"                              # no power-platform/
printf 'not json at all\n' > "$d/.config/dotnet-tools.json"            # unreadable manifest: warn, do not crash
out=$(run "$d")
want "ruff without the notebook exclusion" "$W_RUFF"; want "prettier with only fabric/" "$W_PRETTIER"; want "unparsable tools manifest" "$W_TOOLS"

# 6. pyproject.toml with [tool.ruff] and no ruff config of its own: ours would shadow it
d="$tmp/pyproj"; mkdir -p "$d"
printf '[project]\nname = "x"\n\n[tool.ruff]\nline-length = 100\n' > "$d/pyproject.toml"
out=$(run "$d"); want "pyproject [tool.ruff]" "$W_PYPROJECT"; want "next step" "$W_STEP"
[ -f "$d/ruff.toml" ] || { echo "FAIL: the stack's ruff.toml was not written beside pyproject.toml"; exit 1; }
d="$tmp/pyproj2"; mkdir -p "$d"
printf '[project]\nname = "x"\n\n[tool.pytest.ini_options]\naddopts = "-q"\n' > "$d/pyproject.toml"
out=$(run "$d"); quiet "pyproject.toml without [tool.ruff]"

# 7. .ruff.toml outranks ruff.toml
d="$tmp/dotruff"; mkdir -p "$d"; printf 'line-length = 99\n' > "$d/.ruff.toml"
out=$(run "$d"); want ".ruff.toml lacking the lines" "$W_DOTRUFF"; wantnot ".ruff.toml: no pyproject warning" "$W_PYPROJECT"
cp "$T/ruff.toml" "$d/.ruff.toml"; out=$(run "$d"); wantnot ".ruff.toml carrying the lines" "$W_DOTRUFF"

# 8. a module that is not selected says nothing, however many of these files exist
d="$tmp/other"; mkdir -p "$d"; printf 'line-length = 99\n' > "$d/ruff.toml"
out=$(python3 configure.py --persona solo-experienced --yes --stack python-uv --dir "$d" 2>&1); quiet "another stack"

# 9. the claims the warnings and the doc make, against the real ruff (skipped when it is not installed)
if command -v ruff >/dev/null 2>&1; then
    d="$tmp/real"; mkdir -p "$d"; printf 'x = 1\n' > "$d/a.py"
    printf '[project]\nname = "x"\n\n[tool.ruff]\nline-length = 100\n' > "$d/pyproject.toml"
    cp "$T/ruff.toml" "$d/ruff.toml"
    settings() { (cd "$d" && ruff check --show-settings a.py 2>/dev/null); }
    settings | grep -q '^linter.line_length = 88$' || { echo "FAIL: ruff no longer ignores [tool.ruff] when a ruff.toml exists; the warning is wrong"; exit 1; }
    { printf 'extend = "pyproject.toml"\n'; cat "$T/ruff.toml"; } > "$d/ruff.toml"
    s=$(settings)
    echo "$s" | grep -q '^linter.line_length = 100$' && echo "$s" | grep -q '^file_resolver.force_exclude = true$' \
        && echo "$s" | grep -q 'fabric/\*\*/notebook-content.py' \
        || { echo "FAIL: 'extend = \"pyproject.toml\"' no longer keeps both the user's settings and the stack's exclusions"; exit 1; }
    rm "$d/pyproject.toml"
    ! (cd "$d" && ruff check a.py >/dev/null 2>&1) || { echo "FAIL: ruff now accepts a missing extended file; the doc's caveat is out of date"; exit 1; }
    echo "  real ruff: precedence, the extend fix, and the missing-file caveat all hold"
elif [ -n "${REQUIRE_REAL_TOOLS:-}" ]; then
    echo "FAIL: REQUIRE_REAL_TOOLS is set and ruff is not installed"; exit 1
else
    echo "  SKIP real ruff: not installed"
fi

echo "PASS: existing ruff, prettier and dotnet config is warned about exactly when the stack's lines are missing"
