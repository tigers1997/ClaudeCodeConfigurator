#!/usr/bin/env bash
# CLAUDE.md must render the new `### Repo bootstrap` subsection under
# ## HOW. Guards against the section getting accidentally pruned by a
# future template refactor.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
cmd="$tmp/CLAUDE.md"

grep -q '^### Repo bootstrap$' "$cmd" \
    || { echo "FAIL: ### Repo bootstrap subsection missing"; exit 1; }

# Section must mention the three commit-vs-ignore concerns; if any bullet
# disappears the prose's value drops sharply.
grep -q 'preserve that block' "$cmd" \
    || { echo "FAIL: gitignore-preservation guidance missing"; exit 1; }
grep -q 'settings.local.json' "$cmd" \
    || { echo "FAIL: settings.local.json gitignore note missing"; exit 1; }
grep -q 'Nested upstream clones' "$cmd" \
    || { echo "FAIL: nested-clone guidance missing"; exit 1; }

# Subsection must live before `## Design features` (i.e., under ## HOW).
line_repo=$(grep -n '^### Repo bootstrap$' "$cmd" | cut -d: -f1)
line_design=$(grep -n '^## Design features$' "$cmd" | cut -d: -f1)
[ "$line_repo" -lt "$line_design" ] \
    || { echo "FAIL: Repo bootstrap landed after Design features (line $line_repo vs $line_design)"; exit 1; }

echo "PASS: CLAUDE.md renders ### Repo bootstrap with all three bullets"
