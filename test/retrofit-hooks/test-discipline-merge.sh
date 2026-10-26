#!/usr/bin/env bash
# Retrofit semantics for the discipline profile:
#   1. a project with no permissions.defaultMode gains "default" on re-run,
#      and the [ MERGED ] summary says so;
#   2. a project whose user chose a mode (acceptEdits) keeps it, and the
#      summary says "kept";
#   3. the two env vars are added when absent and a user's own value wins.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Pre-profile project: strip the keys a pre-profile scaffold never had.
python3 configure.py --persona solo-experienced --yes --dir "$tmp/a" >/dev/null
python3 - "$tmp/a/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["permissions"].pop("defaultMode", None)
d["env"].pop("CLAUDE_CODE_FORK_SUBAGENT", None)
d["env"].pop("CLAUDE_CODE_ENABLE_TODO_TOOLS", None)
json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
PY
out=$(python3 configure.py --persona solo-experienced --yes --dir "$tmp/a")
printf '%s\n' "$out" | grep -q "added starting mode (default)" \
    || { echo "FAIL: [ MERGED ] did not report the added starting mode"; printf '%s\n' "$out" | grep -i -A2 MERGED; exit 1; }
python3 - "$tmp/a/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["permissions"]["defaultMode"] == "default", d["permissions"]
assert d["env"]["CLAUDE_CODE_FORK_SUBAGENT"] == "0" and d["env"]["CLAUDE_CODE_ENABLE_TODO_TOOLS"] == "1", d["env"]
print("  pre-profile project: starting mode and env vars added on retrofit")
PY

# 2. A user-chosen mode and env value survive.
python3 configure.py --persona solo-experienced --yes --dir "$tmp/b" >/dev/null
python3 - "$tmp/b/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["permissions"]["defaultMode"] = "acceptEdits"
d["env"]["CLAUDE_CODE_FORK_SUBAGENT"] = "1"
json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
PY
out=$(python3 configure.py --persona solo-experienced --yes --dir "$tmp/b")
printf '%s\n' "$out" | grep -q "kept your starting mode (acceptEdits)" \
    || { echo "FAIL: [ MERGED ] did not report the kept starting mode"; printf '%s\n' "$out" | grep -i -A2 MERGED; exit 1; }
python3 - "$tmp/b/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["permissions"]["defaultMode"] == "acceptEdits", d["permissions"]
assert d["env"]["CLAUDE_CODE_FORK_SUBAGENT"] == "1", d["env"]
print("  user's mode and env value preserved on retrofit")
PY

echo "PASS: discipline profile merges without flipping a user's choices"
