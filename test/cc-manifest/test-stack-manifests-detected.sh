#!/usr/bin/env bash
# Helper detects the known repo-root manifest files and returns them sorted.
set -euo pipefail

proj_root=$(pwd)
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Empty project → empty list
result=$(cd "$tmp" && python3 -c "
import sys; sys.path.insert(0, '$proj_root')
from configure import detect_stack_manifests
from pathlib import Path
print(detect_stack_manifests(Path('.')))
")
[ "$result" = "[]" ] || { echo "FAIL: empty dir should yield []; got: $result"; exit 1; }

# Two manifests present → sorted list
touch "$tmp/package.json" "$tmp/pyproject.toml"
result=$(cd "$tmp" && python3 -c "
import sys; sys.path.insert(0, '$proj_root')
from configure import detect_stack_manifests
from pathlib import Path
print(detect_stack_manifests(Path('.')))
")
[ "$result" = "['package.json', 'pyproject.toml']" ] \
    || { echo "FAIL: expected sorted [package.json, pyproject.toml]; got: $result"; exit 1; }

# Unknown extension is ignored
touch "$tmp/random.txt"
result=$(cd "$tmp" && python3 -c "
import sys; sys.path.insert(0, '$proj_root')
from configure import detect_stack_manifests
from pathlib import Path
print(detect_stack_manifests(Path('.')))
")
[ "$result" = "['package.json', 'pyproject.toml']" ] \
    || { echo "FAIL: random.txt should be ignored; got: $result"; exit 1; }

echo "PASS: detect_stack_manifests scans known filenames only and returns sorted"
