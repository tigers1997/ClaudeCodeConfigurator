#!/usr/bin/env bash
# The freeze made the three PreToolUse guards fail closed (onFailure "block",
# CC 2.1.295+) and moved the microbit enforcer's timeout 5 -> 10 s. A retrofit
# must (1) backfill onFailure onto configurator-owned entries that predate it,
# (2) raise a timeout that still holds the shipped 5, (3) leave a user-tuned
# timeout alone, and (4) never touch the fail-open package-availability gate.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

# Simulate a pre-freeze install: no onFailure anywhere, the enforcer at the
# old 5 s, and a user-tuned 7 s on the secret scan.
python3 - "$tmp/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
for groups in d["hooks"].values():
    for g in groups:
        for h in g.get("hooks", []):
            h.pop("onFailure", None)
            if h["command"].endswith("microbit-enforcer.sh"):
                h["timeout"] = 5
            if h["command"].endswith("scan-secrets.sh"):
                h["timeout"] = 7
json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
PY

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

python3 - "$tmp/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
by = {}
for groups in d["hooks"].values():
    for g in groups:
        for h in g.get("hooks", []):
            by[h["command"].rsplit("/", 1)[-1]] = h
assert by["block-dangerous-bash.sh"].get("onFailure") == "block", by["block-dangerous-bash.sh"]
assert by["scan-secrets.sh"].get("onFailure") == "block", by["scan-secrets.sh"]
assert by["scan-secrets.sh"]["timeout"] == 7, "user-tuned timeout must survive"
assert by["microbit-enforcer.sh"].get("onFailure") == "block", by["microbit-enforcer.sh"]
assert by["microbit-enforcer.sh"]["timeout"] == 10, by["microbit-enforcer.sh"]
assert "onFailure" not in by["check-package-availability.sh"], "availability gate must stay fail-open"
print("  onFailure backfilled on the 3 guards; enforcer 5->10; tuned 7 kept; gate untouched")
PY

echo "PASS: fail-closed guards backfill on retrofit without clobbering user tuning"
