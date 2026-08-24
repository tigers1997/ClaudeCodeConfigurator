#!/usr/bin/env bash
# Verify check_settings_validates() actually catches its regression classes:
# top-level //-prefixed keys, a non-object skillOverrides value, project-scope
# autoMode (ignored since CC 2.1.207) and never-consulted Write()/Glob() rules.
# Constructs synthetic settings dicts and asserts the check fires.
set -euo pipefail

python3 - <<'EOF'
import sys
sys.path.insert(0, '.')
from configure import check_settings_validates

# Case 1: top-level //-prefixed key
bad1 = {"// sandbox": {"foo": "bar"}, "$schema": "x"}
w = check_settings_validates(bad1)
assert any("//" in msg and "schema rejects" in msg for msg in w), f"expected //-leak warning, got: {w}"

# Case 2: nested //-prefixed key (statusLine.// hideVimModeIndicator)
bad2 = {"statusLine": {"// hideVimModeIndicator": True}}
w = check_settings_validates(bad2)
assert any("//" in msg for msg in w), f"expected nested //-leak warning, got: {w}"

# Case 3: skillOverrides as string
bad3 = {"skillOverrides": "name-only"}
w = check_settings_validates(bad3)
assert any("skillOverrides" in msg and "object map" in msg for msg in w), f"expected skillOverrides-shape warning, got: {w}"

# Case 4: skillOverrides as object with invalid value
bad4 = {"skillOverrides": {"my-skill": "unknown-value"}}
w = check_settings_validates(bad4)
assert any("skillOverrides" in msg for msg in w), f"expected skillOverrides-value warning, got: {w}"

# Case 6: autoMode in project settings (ignored by CC >= 2.1.207)
bad6 = {"autoMode": {"hard_deny": ["Running executable files"]}}
w = check_settings_validates(bad6)
assert any("autoMode" in msg and "~/.claude/settings.json" in msg for msg in w), f"expected autoMode-scope warning, got: {w}"

# Case 7: never-consulted path rules (Write/NotebookEdit/Glob/MultiEdit)
bad7 = {"permissions": {"deny": ["Write(.env)", "Edit(.env)"], "allow": ["Glob(src/**)", "Read"]}}
w = check_settings_validates(bad7)
assert any("Write(.env)" in msg and "Glob(src/**)" in msg for msg in w), f"expected path-rule warning, got: {w}"
assert not any("Edit(.env)" in msg for msg in w), f"Edit() rule must not be flagged: {w}"

# Case 5: clean settings — no warnings
clean = {"$schema": "x", "skillOverrides": {"my-skill": "name-only"}, "env": {"FOO": "bar"},
         "permissions": {"deny": ["Edit(.env)", "Read(secrets/**)", "Write"]}}
w = check_settings_validates(clean)
assert w == [], f"expected clean output, got: {w}"

print("PASS: check_settings_validates catches all 6 violation classes + clean case")
EOF
