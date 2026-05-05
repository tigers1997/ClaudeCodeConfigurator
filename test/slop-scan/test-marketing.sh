#!/usr/bin/env bash
set -euo pipefail
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","new_string":"# This is a seamless integration\ndef f(): pass\n"}}' \
      | bash templates/safety/hooks/slop-scan.sh 2>&1 || true)
echo "$out" | grep -q "marketing-voice:" || { echo "FAIL: marketing not detected"; exit 1; }
echo "PASS: marketing detected"
