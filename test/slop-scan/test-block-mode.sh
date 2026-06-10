#!/usr/bin/env bash
# Block mode must surface findings to Claude via PostToolUse decision JSON on
# stdout — {"decision":"block","reason":...} with exit 0 — the documented
# feedback channel (docs/03 "Decision JSON"). The previous exit-1 form was a
# NON-blocking error per the hook exit-code contract: stderr landed in the
# transcript only and Claude never saw the findings, so block mode never
# actually fed anything back.
set -euo pipefail

export SLOP_SCAN_ACTION=block

# Command substitution under set -e doubles as the exit-0 assertion.
out=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","new_string":"# Furthermore the cache is seamless\ndef f(): pass\n"}}' \
      | bash templates/safety/hooks/slop-scan.sh)

echo "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert d.get("decision") == "block", f"decision != block: {d}"
assert "filler:" in d.get("reason", ""), f"findings missing from reason: {d}"
assert "[ SLOP ]" in d.get("reason", ""), f"reason should carry the [ SLOP ] banner: {d}"
'
echo "PASS: block mode emits decision-block JSON (exit 0) with findings in reason"
