#!/usr/bin/env bash
set -euo pipefail
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","new_string":"# Note — see the docs — they explain — everything\ndef f(): pass\n"}}' \
      | bash templates/safety/hooks/slop-scan.sh 2>&1 || true)
echo "$out" | grep -q "em-dash-spam:" || { echo "FAIL: em-dash not detected"; exit 1; }
echo "PASS: em-dash spam detected"
