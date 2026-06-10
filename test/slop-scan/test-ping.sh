#!/usr/bin/env bash
# Findings ping the user out-of-band via the hook-output terminalSequence
# field (CC 2.1.141+): an OSC 9 desktop notification terminated by BEL, both
# on the documented allowlist. Older Claude Code ignores the extra field.
# SLOP_SCAN_PING=0 must omit it entirely. Warn mode (the default) must carry
# the findings in systemMessage so the user actually sees the warning.
set -euo pipefail

payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","new_string":"# perhaps consider a cache here\ndef f(): pass\n"}}'

# --- default: ping on, warn mode → systemMessage + terminalSequence ---
out=$(echo "$payload" | bash templates/safety/hooks/slop-scan.sh)
echo "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert "hedging:" in d.get("systemMessage", ""), f"warn findings missing from systemMessage: {d}"
seq = d.get("terminalSequence", "")
assert seq.startswith("\x1b]9;"), f"expected OSC 9 notification, got {seq!r}"
assert seq.endswith("\x07"), f"sequence must end with BEL, got {seq!r}"
'

# --- SLOP_SCAN_PING=0 → no terminalSequence key ---
out=$(echo "$payload" | SLOP_SCAN_PING=0 bash templates/safety/hooks/slop-scan.sh)
echo "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert "terminalSequence" not in d, f"ping must be omitted when SLOP_SCAN_PING=0: {d}"
assert "hedging:" in d.get("systemMessage", ""), f"findings must still be reported: {d}"
'

echo "PASS: OSC 9 ping present by default, omitted with SLOP_SCAN_PING=0"
