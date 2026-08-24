#!/usr/bin/env bash
# v2.8.0 retired two configurator defaults that current Claude Code ignores:
#   - a project-scope `autoMode` block (CC >= 2.1.207 reads autoMode only from
#     ~/.claude/settings.json / managed settings)
#   - `Write(.env)` / `Write(.env.*)` deny rules (Edit(path) already covers the
#     Write tool; CC >= 2.1.210 warns at startup about Write(path) rules)
# and started declaring `shell: "bash"` on every shipped command hook.
# A retrofit must (1) remove exactly the shipped autoMode block and the two
# Write rules, (2) backfill `shell` onto configurator-owned hook entries that
# predate it, and (3) leave a user-edited autoMode block alone.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

# Simulate a pre-v2.8.0 install: shipped autoMode block, Write(.env*) deny
# rules, and hook entries without the `shell` key.
python3 - "$tmp/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["autoMode"] = {"hard_deny": ["Running executable files", "Writing to system directories"]}
deny = d["permissions"]["deny"]
deny[:0] = ["Write(.env)", "Write(.env.*)"]
for groups in d["hooks"].values():
    for g in groups:
        for h in g.get("hooks", []):
            h.pop("shell", None)
json.dump(d, open(p, "w"), indent=2)
PY

out=$(python3 configure.py --persona solo-experienced --yes --dir "$tmp")

python3 - "$tmp/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert "autoMode" not in d, f"shipped autoMode block survived retrofit: {d.get('autoMode')}"
deny = d["permissions"]["deny"]
assert "Write(.env)" not in deny and "Write(.env.*)" not in deny, f"Write(.env*) rules survived: {deny}"
assert "Edit(.env)" in deny and "Edit(.env.*)" in deny, f"Edit(.env*) rules missing: {deny}"
missing = [h["command"] for groups in d["hooks"].values() for g in groups
           for h in g.get("hooks", []) if h.get("type") == "command" and "shell" not in h]
assert not missing, f"shell not backfilled on: {missing}"
print("  migrated: autoMode removed, Write(.env*) removed, shell backfilled on all hooks")
PY

printf '%s\n' "$out" | grep -q "retired configurator default" \
    || { echo "FAIL: [ MERGED ] summary does not mention the retired defaults"; printf '%s\n' "$out" | grep -i merged; exit 1; }

# --- A user-edited autoMode block must survive (and be flagged, not deleted).
tmp2=$(mktemp -d)
trap "rm -rf $tmp $tmp2" EXIT
python3 configure.py --persona solo-experienced --yes --dir "$tmp2" >/dev/null
python3 - "$tmp2/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["autoMode"] = {"hard_deny": ["Running executable files", "Never run terraform apply"]}
json.dump(d, open(p, "w"), indent=2)
PY
python3 configure.py --persona solo-experienced --yes --dir "$tmp2" >/dev/null
python3 - "$tmp2/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("autoMode") == {"hard_deny": ["Running executable files", "Never run terraform apply"]}, \
    f"user-edited autoMode was altered: {d.get('autoMode')}"
print("  preserved: user-edited autoMode block untouched")
PY

echo "PASS: retired defaults migrate out on retrofit; user-edited autoMode preserved"
