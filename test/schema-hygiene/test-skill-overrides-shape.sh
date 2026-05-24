#!/usr/bin/env bash
# Catch the regression class where a patch ships skillOverrides as a string
# (e.g., "name-only") instead of the schema-required per-skill object map.
# Walks every settings-patch*.json file under templates/ and asserts the
# shape. The configurator's static --check enforces this too; this test
# pins the invariant independently.
set -euo pipefail

fail=0
while IFS= read -r -d '' f; do
    shape=$(python3 -c "
import json, sys
data = json.load(open('$f'))
so = data.get('skillOverrides')
if so is None:
    print('absent')
elif isinstance(so, dict):
    print('object')
else:
    print(f'WRONG: {type(so).__name__} ({so!r})')
")
    case "$shape" in
        absent|object)
            ;;
        *)
            echo "FAIL: $f — $shape"
            fail=1
            ;;
    esac
done < <(find templates -name 'settings-patch*.json' -type f -print0)

[ "$fail" -eq 0 ] || exit 1
echo "PASS: no settings-patch ships skillOverrides as a non-object"
