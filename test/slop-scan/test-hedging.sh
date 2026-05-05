#!/usr/bin/env bash
set -euo pipefail
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","new_string":"# you may want to use bcrypt here\ndef f(): pass\n"}}' \
      | bash templates/safety/hooks/slop-scan.sh 2>&1 || true)
echo "$out" | grep -q "hedging:" || { echo "FAIL: hedging not detected"; exit 1; }
echo "PASS: hedging detected"
