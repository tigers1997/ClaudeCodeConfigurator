#!/usr/bin/env bash
# Regression (dogfood F1): the microbit-enforcer SessionStart marker-clear must
# be scoped to the fresh-slate sources (startup|clear) so that --resume and
# post-compaction SessionStart events do NOT wipe .frozen/.guarded/.careful
# mid-session. With no matcher it fires on every source incl. resume/compact,
# silently un-freezing files in long sessions (exactly when you'd want the
# freeze to hold). SessionStart sources per code.claude.com/docs/en/hooks-guide
# are: startup, resume, clear, compact — the matcher filters on source.
set -euo pipefail

proj_root=$(pwd)

result=$(python3 -c "
import sys, json; sys.path.insert(0, '$proj_root')
from configure import compute_merged_settings
s = compute_merged_settings({}, {'core', 'commands'}, {'commands': {'subset': 'full'}})
ss = s.get('hooks', {}).get('SessionStart', [])
# The entry that clears the discipline markers (identified by the .frozen path).
entry = next((e for e in ss
              if any('.frozen' in h.get('command', '') for h in e.get('hooks', []))),
             None)
print(json.dumps({'found': entry is not None,
                  'matcher': (entry or {}).get('matcher')}))
")

found=$(printf '%s' "$result" | python3 -c "import json,sys;print(json.load(sys.stdin)['found'])")
matcher=$(printf '%s' "$result" | python3 -c "import json,sys;print(json.load(sys.stdin)['matcher'])")

[ "$found" = "True" ] || {
  echo "FAIL: no SessionStart marker-clear entry in commands(subset=full); got: $result"
  exit 1
}
[ "$matcher" = "startup|clear" ] || {
  echo "FAIL: SessionStart marker-clear matcher must be 'startup|clear' (fresh-slate only,"
  echo "      so resume/compact preserve markers); got: '$matcher'"
  exit 1
}

echo "PASS: microbit-enforcer SessionStart marker-clear is scoped to startup|clear (resume/compact preserve markers)"
