#!/usr/bin/env bash
# The safety module's discipline profile (safety.discipline, default true)
# pins the session shape Claude Code had before auto mode became the starting
# mode: permissions.defaultMode "default" plus CLAUDE_CODE_FORK_SUBAGENT=0 and
# CLAUDE_CODE_ENABLE_TODO_TOOLS=1 in env. discipline_mode refines the mode
# (acceptEdits / inspect) and discipline_strict adds disableAutoMode. All of
# it must vanish when discipline is off, and `inspect` must drop the
# whole-tool Write/Edit allow rules on a fresh scaffold.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

settings_of() {  # $1 = scaffold dir
    cat "$1/.claude/settings.json"
}

# 1. Persona default: on.
python3 configure.py --persona solo-experienced --yes --dir "$tmp/p" >/dev/null
settings_of "$tmp/p" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["permissions"]["defaultMode"] == "default", d["permissions"]
assert d["env"]["CLAUDE_CODE_FORK_SUBAGENT"] == "0", d["env"]
assert d["env"]["CLAUDE_CODE_ENABLE_TODO_TOOLS"] == "1", d["env"]
assert "disableAutoMode" not in d, "strict must be off by default"
assert "Write" in d["permissions"]["allow"] and "Edit" in d["permissions"]["allow"]
print("  persona scaffold: defaultMode=default, both env vars, no disableAutoMode")
'

# 2. Bare --modules core,safety (custom persona): the flag default is still on.
python3 configure.py --modules core,safety --yes --dir "$tmp/c" >/dev/null
settings_of "$tmp/c" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["permissions"]["defaultMode"] == "default", d["permissions"]
assert d["env"]["CLAUDE_CODE_FORK_SUBAGENT"] == "0", d["env"]
print("  bare safety scaffold: profile on by flag default")
'

# 3. Flag variants via a saved config: acceptEdits, inspect, strict, off.
python3 configure.py --persona solo-experienced --yes --save-config-only "$tmp/base.json" >/dev/null

variant() {  # $1 = name, $2 = python statements editing `sf` (the safety flags)
    python3 - "$tmp/base.json" "$tmp/$1.json" "$2" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
sf = cfg["module_flags"].setdefault("safety", {})
exec(sys.argv[3], {"sf": sf})
json.dump(cfg, open(sys.argv[2], "w", encoding="utf-8"), indent=1)
PY
    mkdir -p "$tmp/$1"
    python3 configure.py --config "$tmp/$1.json" --yes --dir "$tmp/$1" >/dev/null
}

variant accept 'sf["discipline_mode"] = "acceptEdits"'
settings_of "$tmp/accept" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["permissions"]["defaultMode"] == "acceptEdits", d["permissions"]
assert d["env"]["CLAUDE_CODE_FORK_SUBAGENT"] == "0"
print("  discipline_mode=acceptEdits: defaultMode=acceptEdits, env kept")
'

variant inspect 'sf["discipline_mode"] = "inspect"'
settings_of "$tmp/inspect" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["permissions"]["defaultMode"] == "default", d["permissions"]
allow = d["permissions"]["allow"]
assert "Write" not in allow and "Edit" not in allow, allow
assert "Read" in allow, allow
print("  discipline_mode=inspect: Write/Edit allow rules removed, Read kept")
'

variant strict 'sf["discipline_strict"] = True'
settings_of "$tmp/strict" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d.get("disableAutoMode") == "disable", d.get("disableAutoMode")
assert d["permissions"]["defaultMode"] == "default"
print("  discipline_strict: disableAutoMode=disable")
'

variant off 'sf["discipline"] = False; sf["discipline_strict"] = True; sf["discipline_mode"] = "inspect"'
settings_of "$tmp/off" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert "defaultMode" not in d["permissions"], d["permissions"]
assert "CLAUDE_CODE_FORK_SUBAGENT" not in d["env"] and "CLAUDE_CODE_ENABLE_TODO_TOOLS" not in d["env"], d["env"]
assert "disableAutoMode" not in d, "strict must be inert while discipline is off"
assert "Write" in d["permissions"]["allow"], "inspect must be inert while discipline is off"
print("  discipline=false: no mode, no env vars; strict and inspect inert")
'

echo "PASS: discipline profile renders, refines and switches off correctly"
