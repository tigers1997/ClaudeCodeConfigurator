#!/usr/bin/env bash
# Helper extracts the first binary token of each non-empty command, skipping empty/None.
set -euo pipefail

proj_root=$(pwd)

result=$(python3 -c "
import sys; sys.path.insert(0, '$proj_root')
from configure import extract_first_binaries
import json
print(json.dumps(extract_first_binaries(
    typecheck='tsc --noEmit',
    lint='pnpm run lint',
    test='pnpm test --filter foo',
), sort_keys=True))
")
expected='{"lint": "pnpm", "test": "pnpm", "typecheck": "tsc"}'
[ "$result" = "$expected" ] || { echo "FAIL: $result != $expected"; exit 1; }

# Empty/None values are skipped (key absent from output, not present-as-null)
result=$(python3 -c "
import sys; sys.path.insert(0, '$proj_root')
from configure import extract_first_binaries
import json
print(json.dumps(extract_first_binaries(typecheck='', lint=None, test='pytest'), sort_keys=True))
")
expected='{"test": "pytest"}'
[ "$result" = "$expected" ] || { echo "FAIL: empty/None not skipped: $result != $expected"; exit 1; }

# Whitespace-only is treated as empty
result=$(python3 -c "
import sys; sys.path.insert(0, '$proj_root')
from configure import extract_first_binaries
import json
print(json.dumps(extract_first_binaries(typecheck='   ', lint='ruff check', test='')))
")
expected='{"lint": "ruff"}'
[ "$result" = "$expected" ] || { echo "FAIL: whitespace not skipped: $result != $expected"; exit 1; }

# Malformed quote must not crash (B1): degrades to a plain split, first token kept
result=$(python3 -c "
import sys; sys.path.insert(0, '$proj_root')
from configure import extract_first_binaries
import json
print(json.dumps(extract_first_binaries(test=\"pnpm test --grep 'foo\")))
")
expected='{"test": "pnpm"}'
[ "$result" = "$expected" ] || { echo "FAIL: malformed quote should degrade, not crash: $result != $expected"; exit 1; }

echo "PASS: extract_first_binaries pulls first token, skips empty/None/whitespace, survives malformed quotes"
