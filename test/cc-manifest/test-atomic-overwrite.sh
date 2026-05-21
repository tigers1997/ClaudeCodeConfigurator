#!/usr/bin/env bash
# Re-running cc-configure overwrites the manifest cleanly: written_at
# updates, no leftover .tmp file, no partial-write corruption.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
manifest="$tmp/.claude/.cc-manifest.json"
first_written=$(jq -r '.written_at' "$manifest")

# Sleep 1s so written_at can advance (ISO 8601 with second precision).
sleep 1

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
second_written=$(jq -r '.written_at' "$manifest")

[ "$first_written" != "$second_written" ] \
    || { echo "FAIL: written_at unchanged across runs"; exit 1; }

# No leftover tmp file (atomic write via .tmp + replace)
[ ! -f "$tmp/.claude/.cc-manifest.json.tmp" ] \
    || { echo "FAIL: .cc-manifest.json.tmp left on disk"; exit 1; }

# Manifest is still valid JSON
jq -e '.manifest_version == 2' "$manifest" >/dev/null \
    || { echo "FAIL: manifest invalid after re-run"; cat "$manifest"; exit 1; }

echo "PASS: manifest atomically overwritten on re-run"
