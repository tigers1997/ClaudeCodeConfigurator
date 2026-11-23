#!/usr/bin/env bash
# Retrofitting agents-md onto a repo that already has a CLAUDE.md. The run must
# not rewrite that CLAUDE.md or auto-insert the import (the file usually states
# the same project facts, so importing AGENTS.md would load them twice). It must
# say that Claude Code will not read AGENTS.md until the import is added.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run() { python3 configure.py --persona solo-experienced --yes --harness agents-md "$@" 2>&1; }

# 1. Existing CLAUDE.md without the import, plus the user's own AGENTS.md.
d="$tmp/a"; mkdir -p "$d"
printf '# Existing project\n\nOur own rules.\n' > "$d/CLAUDE.md"
printf '# Existing AGENTS\n\nOur own agent rules.\n' > "$d/AGENTS.md"
out=$(run --dir "$d")
echo "$out" | grep -q 'does not import AGENTS.md' || { echo "FAIL: no bridge warning"; echo "$out"; exit 1; }
echo "$out" | grep -q 'Add `@AGENTS.md` to your existing CLAUDE.md' || { echo "FAIL: no NEXT STEPS line"; exit 1; }
[ "$(head -n1 "$d/CLAUDE.md")" = "# Existing project" ] \
    || { echo "FAIL: CLAUDE.md was rewritten or had the import prepended"; head -3 "$d/CLAUDE.md"; exit 1; }
grep -qxF '@AGENTS.md' "$d/CLAUDE.md" && { echo "FAIL: import auto-inserted"; exit 1; }
grep -q 'Our own rules.' "$d/CLAUDE.md" || { echo "FAIL: user CLAUDE.md content lost"; exit 1; }
[ "$(cat "$d/AGENTS.md")" = "$(printf '# Existing AGENTS\n\nOur own agent rules.')" ] \
    || { echo "FAIL: user AGENTS.md was overwritten"; exit 1; }
[ -f "$d/.claude-retrofit/incoming/AGENTS.md" ] || { echo "FAIL: our AGENTS.md not staged"; exit 1; }
grep -q 'Needs your attention' "$d/.claude-retrofit/REPORT.md" \
    || { echo "FAIL: REPORT.md has no 'Needs your attention' section"; exit 1; }
grep -q 'does not import AGENTS.md' "$d/.claude-retrofit/REPORT.md" \
    || { echo "FAIL: REPORT.md does not carry the bridge note"; exit 1; }

# 2. CLAUDE.md that already imports AGENTS.md: silent.
d="$tmp/b"; mkdir -p "$d"
printf '@AGENTS.md\n\n# Mine\n' > "$d/CLAUDE.md"
out=$(run --dir "$d")
echo "$out" | grep -q 'does not import AGENTS.md' && { echo "FAIL: warned although CLAUDE.md imports AGENTS.md"; exit 1; }

# 3. --claude-md overwrite: the bridge replaces the file (original backed up), silent.
d="$tmp/c"; mkdir -p "$d"
printf '# Mine\n' > "$d/CLAUDE.md"
out=$(run --claude-md overwrite --dir "$d")
echo "$out" | grep -q 'does not import AGENTS.md' && { echo "FAIL: warned although the bridge replaces CLAUDE.md"; exit 1; }
[ "$(head -n1 "$d/CLAUDE.md")" = "@AGENTS.md" ] || { echo "FAIL: overwrite did not install the bridge"; exit 1; }

# 4. Fresh target: silent, and no retrofit report at all.
d="$tmp/d"; mkdir -p "$d"
out=$(run --dir "$d")
echo "$out" | grep -q 'does not import AGENTS.md' && { echo "FAIL: warned on a fresh target"; exit 1; }
[ ! -e "$d/.claude-retrofit" ] || { echo "FAIL: fresh target produced a retrofit report"; exit 1; }

echo "PASS: retrofit leaves CLAUDE.md alone, warns when it cannot reach AGENTS.md, and is silent otherwise"
