#!/usr/bin/env bash
# validate.sh: headless validation for Fabric, Power BI and Power Platform source.
#
# Every tier reports OK, FAIL or SKIP, and says which. A tier whose tool is
# missing is SKIP, never a quiet pass.
#
#   repo      .platform identity files, committed Power BI cache files     python3
#   models    TMDL structure of every *.SemanticModel/definition           .NET 10 SDK (TOM parser)
#   report    PBIR schema of every *.Report                                Node 20+ (powerbi-report-author)
#   solution  `pac solution pack` of every Power Platform solution root    pac (offline)
#   python    ruff and pytest, when the repo has Python                    uv, or ruff/pytest on PATH
#
# What these checks do NOT do: validate DAX or M, or find circular measure
# dependencies. The TMDL parser reads expressions verbatim, so a measure with
# unbalanced parentheses or an undefined function passes. Nothing offline
# validates DAX; docs/microsoft-data-stack.md says what does.
#
# usage: ./scripts/validate.sh [--changed] [--strict] [TIER ...]
#   --changed  only the tiers whose files changed since HEAD (plus untracked
#              files); silent when none did. The Stop hook uses this.
#   --strict   a SKIP counts as a failure. Use it in CI.
# exit: 0 no FAIL (and, with --strict, no SKIP) | 1 FAIL, or SKIP under --strict | 2 bad usage
set -uo pipefail

# Exact pin: the package is a public preview and its own README says to pin.
PBIR_CLI_VERSION="0.5.0"
DOTNET_MIN_MAJOR=10
NODE_MIN_MAJOR=20

export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2

CHANGED_ONLY=0
STRICT=0
TIERS=()
for arg in "$@"; do
  case "$arg" in
    --changed) CHANGED_ONLY=1 ;;
    --strict)  STRICT=1 ;;
    --all)     ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    repo|models|report|solution|python) TIERS+=("$arg") ;;
    *) echo "validate.sh: unknown argument '$arg' (tiers: repo models report solution python)" >&2; exit 2 ;;
  esac
done
[ "${#TIERS[@]}" -gt 0 ] || TIERS=(repo models report solution python)

# --- what changed ------------------------------------------------------------
# Uncommitted changes against HEAD plus untracked files. Outside a git repo, or
# before the first commit, everything counts as changed.
CHANGED_LIST=""
if [ "$CHANGED_ONLY" = 1 ]; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
      CHANGED_LIST="$(git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)"
    else
      CHANGED_LIST="$(git ls-files 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)"
    fi
  else
    CHANGED_ONLY=0
  fi
fi

# changed_under PREFIX...: true when any changed path starts with a prefix.
changed_under() {
  [ "$CHANGED_ONLY" = 0 ] && return 0
  local p
  for p in "$@"; do
    printf '%s\n' "$CHANGED_LIST" | awk -v p="$p" 'index($0, p) == 1 { f = 1 } END { exit !f }' && return 0
  done
  return 1
}

# changed_in PART...: true when any changed path contains a part, e.g. ".Report/".
changed_in() {
  [ "$CHANGED_ONLY" = 0 ] && return 0
  local s
  for s in "$@"; do
    printf '%s\n' "$CHANGED_LIST" | awk -v s="$s" 'index($0, s) > 0 { f = 1 } END { exit !f }' && return 0
  done
  return 1
}

# changed_ext SUFFIX...: true when any changed path ends with a suffix.
changed_ext() {
  [ "$CHANGED_ONLY" = 0 ] && return 0
  local s
  for s in "$@"; do
    printf '%s\n' "$CHANGED_LIST" | awk -v s="$s" 'length($0) >= length(s) && substr($0, length($0) - length(s) + 1) == s { f = 1 } END { exit !f }' && return 0
  done
  return 1
}

# --- reporting -----------------------------------------------------------------
FAILED=0
SKIPPED=0
say()       { printf '[validate] %-9s %-4s %s\n' "$1" "$2" "$3"; }
tier_ok()   { say "$1" OK "$2"; }
tier_fail() { say "$1" FAIL "$2"; FAILED=1; }
tier_skip() { say "$1" SKIP "$2"; SKIPPED=1; }
detail()    { sed 's/^/    /' | head -n "${1:-30}"; }

TMP_DIR=""
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"; return 0; }
trap cleanup EXIT

# list_dirs ROOT NAME-GLOB: directories under ROOT, sorted, one per line.
list_dirs() {
  [ -d "$1" ] || return 0
  find "$1" -type d -name "$2" -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | LC_ALL=C sort
}

major_of() { local v="${1%%.*}"; case "$v" in ''|*[!0-9]*) echo 0 ;; *) echo "$v" ;; esac; }

# --- tier: repo ------------------------------------------------------------------
tier_repo() {
  [ -d fabric ] || [ -d power-platform ] || return 0
  changed_under fabric/ power-platform/ .gitignore || return 0
  command -v python3 >/dev/null 2>&1 || { tier_skip repo "python3 not found"; return; }
  local out rc
  out="$(python3 "$SCRIPT_DIR/check_fabric_items.py" --root . 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    tier_ok repo "$(printf '%s\n' "$out" | grep '^SUMMARY' | sed 's/^SUMMARY //')"
    printf '%s\n' "$out" | grep '^WARN' | detail 12
  else
    tier_fail repo "identity or hygiene problems"
    printf '%s\n' "$out" | grep -E '^(FAIL|WARN)' | detail 40
  fi
}

# --- tier: models ----------------------------------------------------------------
tier_models() {
  local defs=() d
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d/definition" ] && defs+=("$d/definition")
  done <<EOF
$(list_dirs fabric '*.SemanticModel')
EOF
  [ "${#defs[@]}" -gt 0 ] || return 0
  changed_in .SemanticModel/ || return 0
  command -v dotnet >/dev/null 2>&1 || { tier_skip models "dotnet not found; the TMDL parse needs the .NET $DOTNET_MIN_MAJOR SDK (docs/microsoft-data-stack.md)"; return; }
  local ver major out rc
  ver="$(dotnet --version 2>/dev/null | head -n1)"; major="$(major_of "$ver")"
  [ "$major" -ge "$DOTNET_MIN_MAJOR" ] || { tier_skip models ".NET SDK '$ver' is too old: scripts/tmdl-check.cs is a file-based app and needs $DOTNET_MIN_MAJOR or later"; return; }
  out="$(dotnet run "$SCRIPT_DIR/tmdl-check.cs" -- "${defs[@]}" 2>&1)"; rc=$?
  if printf '%s\n' "$out" | grep -q '^FAIL '; then
    tier_fail models "TMDL does not parse (structure only; DAX and M are not checked)"
    printf '%s\n' "$out" | grep -vE '^OK ' | detail 40
  elif printf '%s\n' "$out" | grep -q '^OK '; then
    tier_ok models "${#defs[@]} model(s) parse as TMDL (structure only; DAX and M are not checked)"
  else
    # No verdict line: the tool never ran (offline NuGet restore, build error).
    # That is an environment problem, not a verdict on the model.
    local why; why="$(printf '%s\n' "$out" | head -n 1 | cut -c1-160)"
    if [ "$STRICT" = 1 ]; then tier_fail models "tmdl-check did not run (exit $rc): $why"; else tier_skip models "tmdl-check did not run (exit $rc): $why"; fi
  fi
}

# --- tier: report ----------------------------------------------------------------
tier_report() {
  local reports=() d
  while IFS= read -r d; do [ -n "$d" ] && reports+=("$d"); done <<EOF
$(list_dirs fabric '*.Report')
EOF
  [ "${#reports[@]}" -gt 0 ] || return 0
  changed_in .Report/ || return 0
  command -v python3 >/dev/null 2>&1 || { tier_skip report "python3 not found"; return; }
  local runner=()
  if command -v powerbi-report-author >/dev/null 2>&1; then
    runner=(powerbi-report-author)
  elif command -v npx >/dev/null 2>&1 && command -v node >/dev/null 2>&1 \
       && [ "$(major_of "$(node --version 2>/dev/null | sed 's/^v//')")" -ge "$NODE_MIN_MAJOR" ]; then
    runner=(npx --yes "--package=@microsoft/powerbi-report-authoring-cli@$PBIR_CLI_VERSION" -- powerbi-report-author)
  else
    tier_skip report "powerbi-report-author not found, and no Node $NODE_MIN_MAJOR+ with npx to fetch version $PBIR_CLI_VERSION"
    return
  fi
  local bad=0 unrun=0 out rc lines msg="" notes=""
  for d in "${reports[@]}"; do
    # Install scripts stay off: this fetches a third-party package.
    out="$(env npm_config_ignore_scripts=true "${runner[@]}" validate "$d" 2>&1)"
    lines="$(printf '%s\n' "$out" | python3 "$SCRIPT_DIR/report_diagnostics.py")"; rc=$?
    if [ "$rc" -eq 3 ]; then unrun=1; msg="$d: $lines"
    elif [ "$rc" -ne 0 ]; then bad=1; notes="$notes$d"$'\n'"$(printf '%s\n' "$lines" | sed 's/^/  /')"$'\n'
    fi
  done
  if [ "$bad" = 1 ]; then
    tier_fail report "PBIR does not validate (schema and structure; field bindings are not checked)"
    printf '%s' "$notes" | detail 40
  elif [ "$unrun" = 1 ]; then
    if [ "$STRICT" = 1 ]; then tier_fail report "powerbi-report-author did not run: $msg"; else tier_skip report "powerbi-report-author did not run: $msg"; fi
  else tier_ok report "${#reports[@]} report(s) validate against the PBIR schemas"; fi
}

# --- tier: solution ----------------------------------------------------------------
# A "pack root" is the folder `pac solution pack --folder` reads: it holds
# solutions/<Name>/solution.yml (YAML layout, from Power Platform Git
# integration) or Other/Solution.xml (the layout `pac solution unpack` writes).
pack_roots() {
  [ -d power-platform ] || return 0
  {
    find power-platform -type f -name solution.yml -path '*/solutions/*/solution.yml' 2>/dev/null | sed 's#/solutions/[^/]*/solution\.yml$##'
    find power-platform -type f -path '*/Other/Solution.xml' 2>/dev/null | sed 's#/Other/Solution\.xml$##'
  } | LC_ALL=C sort -u
}

# What `pac solution pack` prints when it is unhappy but still exits 0. Observed
# with pac 2.16.1: a root component whose files are missing prints
#   "Following root components are not defined in customizations:"
# and exits 0 with a zip, with no "warning" label at all. The packer's own docs
# also describe warnings for omitted components. So this matches the observed
# text and the generic words, not just "warning". Lines that only echo a path
# (Packing ...) and the version banner are excluded first.
PAC_TROUBLE='(^[[:space:]]*(warning|error)\b|not defined in|cannot find|could not|is missing|are missing|omitted)'

tier_solution() {
  local roots=() r
  while IFS= read -r r; do [ -n "$r" ] && roots+=("$r"); done <<EOF
$(pack_roots)
EOF
  [ "${#roots[@]}" -gt 0 ] || return 0
  changed_under power-platform/ || return 0
  local pac=()
  if command -v pac >/dev/null 2>&1; then
    pac=(pac)
  elif command -v dotnet >/dev/null 2>&1 && [ -f .config/dotnet-tools.json ] && dotnet tool run pac help >/dev/null 2>&1; then
    pac=(dotnet tool run pac)
  else
    tier_skip solution "pac not found: run 'dotnet tool restore' (pins pac in .config/dotnet-tools.json)"
    return
  fi
  TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
  local n=0 bad=0 out rc trouble notes=""
  for r in "${roots[@]}"; do
    n=$((n + 1))
    out="$("${pac[@]}" solution pack --folder "$r" --zipfile "$TMP_DIR/pack-$n.zip" --packagetype Unmanaged 2>&1)"; rc=$?
    trouble="$(printf '%s\n' "$out" | grep -vE '^(Packing |Microsoft PowerPlatform|Version:|Online documentation|Feedback)' | grep -iE "$PAC_TROUBLE")"
    if [ "$rc" -ne 0 ]; then
      bad=1; notes="$notes$r: pac exited $rc"$'\n'"$(printf '%s\n' "$out" | grep -vE '^(Microsoft PowerPlatform|Version:|Online documentation|Feedback|$)' | tail -n 8 | sed 's/^/  /')"$'\n'
    elif [ -n "$trouble" ]; then
      bad=1; notes="$notes$r: pac exited 0 but reported a problem"$'\n'"$(printf '%s\n' "$trouble" | head -n 8 | sed 's/^/  /')"$'\n'
    fi
  done
  if [ "$bad" = 1 ]; then
    tier_fail solution "pack failed or reported missing components (pack success is not import success)"
    printf '%s' "$notes" | detail 40
  else tier_ok solution "${#roots[@]} solution root(s) pack cleanly (offline; not a solution-checker run)"; fi
}

# --- tier: python ------------------------------------------------------------------
tier_python() {
  [ -f pyproject.toml ] || [ -d tests ] || return 0
  changed_ext .py pyproject.toml || return 0
  local out rc=0 ran=""
  if [ -f pyproject.toml ] && command -v uv >/dev/null 2>&1; then
    out="$(uv run --quiet ruff check . 2>&1)" || { tier_fail python "ruff check"; printf '%s\n' "$out" | detail 25; return; }
    ran="ruff"
    if [ -d tests ]; then
      out="$(uv run --quiet pytest -q 2>&1)"; rc=$?
      [ "$rc" -eq 5 ] && rc=0   # pytest exit 5: nothing collected
      [ "$rc" -eq 0 ] || { tier_fail python "pytest"; printf '%s\n' "$out" | tail -n 25 | detail 25; return; }
      ran="ruff, pytest"
    fi
  elif command -v ruff >/dev/null 2>&1 || command -v pytest >/dev/null 2>&1; then
    if command -v ruff >/dev/null 2>&1; then
      out="$(ruff check . 2>&1)" || { tier_fail python "ruff check"; printf '%s\n' "$out" | detail 25; return; }
      ran="ruff"
    fi
    if [ -d tests ] && command -v pytest >/dev/null 2>&1; then
      out="$(pytest -q 2>&1)"; rc=$?
      [ "$rc" -eq 5 ] && rc=0
      [ "$rc" -eq 0 ] || { tier_fail python "pytest"; printf '%s\n' "$out" | tail -n 25 | detail 25; return; }
      ran="${ran:+$ran, }pytest"
    fi
  fi
  if [ -n "$ran" ]; then tier_ok python "$ran"; else tier_skip python "neither uv nor ruff/pytest found"; fi
}

for tier in "${TIERS[@]}"; do
  case "$tier" in
    repo) tier_repo ;;
    models) tier_models ;;
    report) tier_report ;;
    solution) tier_solution ;;
    python) tier_python ;;
  esac
done

if [ "$FAILED" = 1 ]; then exit 1; fi
if [ "$STRICT" = 1 ] && [ "$SKIPPED" = 1 ]; then
  echo "[validate] --strict: a tier was skipped, so this is not a pass" >&2
  exit 1
fi
exit 0
