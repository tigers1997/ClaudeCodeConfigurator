#!/usr/bin/env bash
# Verify check_settings_validates() actually catches the two regression
# classes: top-level //-prefixed keys and a non-object skillOverrides value.
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

# Case 5: clean settings — no warnings
clean = {"$schema": "x", "skillOverrides": {"my-skill": "name-only"}, "env": {"FOO": "bar"}}
w = check_settings_validates(clean)
assert w == [], f"expected clean output, got: {w}"

print("PASS: check_settings_validates catches all 4 violation classes + clean case")
EOF
