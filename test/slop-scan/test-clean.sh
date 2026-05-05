#!/usr/bin/env bash
set -euo pipefail
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","new_string":"def add(a, b):\n    return a + b\n"}}' \
      | bash templates/safety/hooks/slop-scan.sh 2>&1)
[[ -z "$out" ]] || { echo "FAIL: clean code should produce no output; got: $out"; exit 1; }
echo "PASS: clean code → no SLOP block"
