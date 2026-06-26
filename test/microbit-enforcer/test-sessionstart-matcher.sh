#!/usr/bin/env bash
# Regression (dogfood F1): the microbit-enforcer SessionStart marker-clear must
# be scoped to the fresh-slate sources (startup|clear) so that --resume and
# post-compaction SessionStart events do NOT wipe .frozen/.guarded/.careful
# mid-session. With no matcher it fires on every source incl. resume/compact,
# silently un-freezing files in long sessions (exactly when you'd want the
# freeze to hold). SessionStart sources per code.claude.com/docs/en/hooks-guide
# are: startup, resume, clear, compact — the matcher filters on source.
set -euo pipefail

python3 - <<'EOF'
import sys
sys.path.insert(0, '.')
from configure import compute_merged_settings

s = compute_merged_settings({}, {"core", "commands"}, {"commands": {"subset": "full"}})
ss = s.get("hooks", {}).get("SessionStart", [])
# The entry that clears the discipline markers (identified by the .frozen path).
entry = next((e for e in ss
              if any(".frozen" in h.get("command", "") for h in e.get("hooks", []))), None)

assert entry is not None, f"no SessionStart marker-clear entry in commands(subset=full): {ss}"
assert entry.get("matcher") == "startup|clear", (
    "SessionStart marker-clear matcher must be 'startup|clear' (fresh-slate only, "
    f"so resume/compact preserve markers); got {entry.get('matcher')!r}")

print("PASS: microbit-enforcer SessionStart marker-clear is scoped to startup|clear (resume/compact preserve markers)")
EOF
