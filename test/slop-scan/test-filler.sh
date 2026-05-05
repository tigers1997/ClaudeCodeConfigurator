#!/usr/bin/env bash
set -euo pipefail
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","new_string":"# It is important to note that this caches\ndef f(): pass\n"}}' \
      | bash templates/safety/hooks/slop-scan.sh 2>&1 || true)
echo "$out" | grep -q "filler:" || { echo "FAIL: filler not detected; got: $out"; exit 1; }
echo "PASS: filler detected"
