#!/usr/bin/env bash
# Scaffold every persona and assert the rendered .claude/settings.json has
# ZERO `//`-prefixed keys at any nesting depth. Catches the regression class
# where a future patch adds a `// foo` stub that escapes _strip_doc_labels.
#
# Dogfood origin: 2026-05-24 — downstream project's editor flagged validator
# complaints on `// sandbox`, `// env`, `// prUrlTemplate`, `// subagentStatusLine`
# keys that the configurator was writing directly to disk.
set -euo pipefail

fail=0
for persona in solo-newer solo-experienced small-team library-author custom; do
    target=$(mktemp -d)
    python3 configure.py --persona "$persona" --yes --dir "$target" >/dev/null
    leaks=$(python3 -c "
import json, sys
def walk(o, prefix=''):
    if isinstance(o, dict):
        for k, v in o.items():
            here = f'{prefix}.{k}' if prefix else k
            if isinstance(k, str) and k.startswith('//'):
                print(here)
            walk(v, here)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            walk(v, f'{prefix}[{i}]')
walk(json.load(open('$target/.claude/settings.json')))
")
    if [ -n "$leaks" ]; then
        echo "FAIL: persona=$persona has //-prefixed keys in settings.json:"
        echo "$leaks" | sed 's/^/  /'
        fail=1
    fi
    rm -rf "$target"
done

[ "$fail" -eq 0 ] || exit 1
echo "PASS: all 5 personas produce settings.json with zero //-prefixed keys"
