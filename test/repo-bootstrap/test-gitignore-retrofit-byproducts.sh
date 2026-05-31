#!/usr/bin/env bash
# F5 (dogfood 2026-05-30): the scaffolded .gitignore must exclude the
# configurator's OWN retrofit byproducts — the `.claude-retrofit/` staging tree
# (skip-mode incoming/ + REPORT.md) and `*.bak-<ts>` backups — so an accidental
# `git add -A` mid-retrofit can't commit them and they don't pile up across
# upgrades. Verifies the template ships them, a fresh scaffold writes them, and
# an existing-user retrofit picks them up via the line-level union (no dup block).
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

append="templates/core/.gitignore.append"

# (a) Template ships both patterns.
grep -qxF '.claude-retrofit/' "$append" || { echo "FAIL: .claude-retrofit/ missing from $append"; exit 1; }
grep -qxF '*.bak-*' "$append"          || { echo "FAIL: *.bak-* missing from $append"; exit 1; }

# (b) A fresh scaffold writes both into the project .gitignore.
python3 configure.py --persona solo-experienced --yes --dir "$tmp/fresh" >/dev/null 2>&1
gi="$tmp/fresh/.gitignore"
grep -qxF '.claude-retrofit/' "$gi" || { echo "FAIL: fresh .gitignore missing .claude-retrofit/"; cat "$gi"; exit 1; }
grep -qxF '*.bak-*' "$gi"          || { echo "FAIL: fresh .gitignore missing *.bak-*"; cat "$gi"; exit 1; }

# (c) Existing user: a .gitignore that already has the Claude Code block but
# predates these lines gets them added (line-level union), and the sentinel
# block is NOT duplicated.
mkdir -p "$tmp/exist"
cat > "$tmp/exist/.gitignore" <<'EOF'
node_modules/

# --- Claude Code ---
.claude/settings.local.json
CLAUDE.local.md
EOF
python3 configure.py --persona solo-experienced --yes --dir "$tmp/exist" >/dev/null 2>&1
egi="$tmp/exist/.gitignore"
grep -qxF '.claude-retrofit/' "$egi" || { echo "FAIL: existing-user retrofit didn't add .claude-retrofit/"; cat "$egi"; exit 1; }
grep -qxF '*.bak-*' "$egi"          || { echo "FAIL: existing-user retrofit didn't add *.bak-*"; cat "$egi"; exit 1; }
n_sentinel=$(grep -cF -- '--- Claude Code ---' "$egi")
[ "$n_sentinel" = "1" ] || { echo "FAIL: Claude Code block duplicated ($n_sentinel sentinels)"; cat "$egi"; exit 1; }
# User's own pre-existing entry preserved.
grep -qxF 'node_modules/' "$egi" || { echo "FAIL: user's node_modules/ line lost"; cat "$egi"; exit 1; }

echo "PASS: .gitignore excludes .claude-retrofit/ + *.bak-* (template, fresh scaffold, existing-user union; no dup block)"
