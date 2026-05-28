#!/usr/bin/env bash
# With stub binaries on PATH, chip should include the right tool versions.
set -euo pipefail

LIB="$PWD/templates/safety/hooks/_lib/detect_tool_versions.sh"
STUBS="$PWD/test/availability-check/fixtures/stub-bin"

result=$(PATH="$STUBS:/usr/bin:/bin" bash -c "source '$LIB' && emit_version_chip")
echo "got: '$result'"

for expected in pg17 node20 py3.13; do
  if ! echo "$result" | grep -q "$expected"; then
    echo "FAIL: chip missing '$expected': '$result'"; exit 1
  fi
done
echo "PASS: chip includes pg17, node20, py3.13"
