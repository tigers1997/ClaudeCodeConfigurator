#!/usr/bin/env bash
# Forked SKILL.md files must NOT contain `superpowers:` prefixed
# cross-references — those were stripped so the skills resolve correctly when
# shipped as project-level skills. Catches regressions on upstream sync.
#
# Allowlist: the SYNC.md maintainer-internal doc deliberately mentions the
# prefix when documenting what was stripped; the LICENSE has none.
set -euo pipefail

cd templates/discipline-skills

fail=0
# Check every shipped file (not SYNC.md, not LICENSE). Use -print0 + while
# loop so filenames with whitespace are handled safely (future-proofing).
while IFS= read -r -d '' f; do
    if grep -n 'superpowers:' "$f" >/dev/null; then
        echo "FAIL: $f contains 'superpowers:' prefix — strip on upstream sync:"
        grep -n 'superpowers:' "$f" | head -3
        fail=1
    fi
done < <(find . -type f \( -name 'SKILL.md' -o -name '*-prompt.md' \) -print0)

[ "$fail" -eq 0 ] || exit 1
echo "PASS: no superpowers: prefix in shipped SKILL.md / prompt templates"
