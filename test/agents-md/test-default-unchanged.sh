#!/usr/bin/env bash
# A Claude-only scaffold must not change: no AGENTS.md, no GEMINI.md, and a
# single self-contained CLAUDE.md. Harness selection is opt-in, never a default
# of any persona, and removable again with --harness claude-code.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for p in solo-newer solo-experienced small-team library-author custom; do
    python3 configure.py --persona "$p" --yes --dir "$tmp/$p" >/dev/null
    for f in AGENTS.md GEMINI.md; do
        [ ! -e "$tmp/$p/$f" ] || { echo "FAIL: persona $p wrote $f without a harness"; exit 1; }
    done
    first=$(head -n1 "$tmp/$p/CLAUDE.md")
    [ "$first" != "@AGENTS.md" ] || { echo "FAIL: persona $p CLAUDE.md imports AGENTS.md"; exit 1; }
    grep -q '^## WHY' "$tmp/$p/CLAUDE.md" \
        || { echo "FAIL: persona $p CLAUDE.md lost its project-facts sections"; exit 1; }
    grep -q '^### Repo bootstrap$' "$tmp/$p/CLAUDE.md" \
        || { echo "FAIL: persona $p CLAUDE.md lost '### Repo bootstrap'"; exit 1; }
done

# --harness claude-code clears a previously selected harness from the saved config.
python3 configure.py --persona solo-experienced --yes --harness gemini --dir "$tmp/h" >/dev/null
python3 configure.py --yes --harness claude-code --dir "$tmp/h" >/dev/null
python3 - "$tmp/h/.claude-config.json" <<'PY'
import json, sys
sel = set(json.load(open(sys.argv[1]))["selected"])
bad = sel & {"agents-md", "gemini-cli"}
assert not bad, f"--harness claude-code left {bad} selected"
PY

echo "PASS: Claude-only scaffolds are unchanged and --harness claude-code clears the harness modules"
