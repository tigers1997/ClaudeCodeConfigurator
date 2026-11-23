#!/usr/bin/env bash
# The Gemini CLI adapter is a GEMINI.md that imports AGENTS.md (Gemini reads
# GEMINI.md by default, AGENTS.md only when context.fileName lists it). It
# depends on agents-md, so selecting it must pull the shared base in too.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 configure.py --persona solo-experienced --yes --harness gemini --dir "$tmp/a" >/dev/null
[ -f "$tmp/a/GEMINI.md" ] || { echo "FAIL: GEMINI.md not written for --harness gemini"; exit 1; }
grep -qxF '@./AGENTS.md' "$tmp/a/GEMINI.md" \
    || { echo "FAIL: GEMINI.md does not import ./AGENTS.md"; cat "$tmp/a/GEMINI.md"; exit 1; }
[ -f "$tmp/a/AGENTS.md" ] || { echo "FAIL: AGENTS.md missing: gemini-cli's dependsOn did not pull agents-md in"; exit 1; }
[ "$(head -n1 "$tmp/a/CLAUDE.md")" = "@AGENTS.md" ] \
    || { echo "FAIL: CLAUDE.md bridge missing with --harness gemini"; exit 1; }
if grep -n '{{' "$tmp/a/GEMINI.md"; then
    echo "FAIL: unresolved placeholder in GEMINI.md"; exit 1
fi

# The module route reaches the same place: --modules +gemini-cli resolves its dependency.
python3 configure.py --persona solo-experienced --yes --dir "$tmp/b" >/dev/null
python3 configure.py --yes --modules +gemini-cli --dir "$tmp/b" >/dev/null
[ -f "$tmp/b/GEMINI.md" ] && [ -f "$tmp/b/AGENTS.md" ] \
    || { echo "FAIL: --modules +gemini-cli did not write GEMINI.md and AGENTS.md"; exit 1; }

echo "PASS: gemini adapter imports AGENTS.md and pulls in its agents-md dependency"
