#!/usr/bin/env bash
set -euo pipefail
export SLOP_SCAN_ACTION=block
if echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","new_string":"# Furthermore the cache is seamless\ndef f(): pass\n"}}' \
   | bash templates/safety/hooks/slop-scan.sh 2>/dev/null; then
  echo "FAIL: block mode should reject"; exit 1
fi
echo "PASS: block mode rejects on slop"
