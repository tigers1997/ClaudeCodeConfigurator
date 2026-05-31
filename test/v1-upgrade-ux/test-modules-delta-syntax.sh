#!/usr/bin/env bash
# F2 Part A (dogfood 2026-05-30): `--modules` gains a delta form. Signed tokens
# (+x,-y) adjust the loaded/saved `selected` set; bare tokens (x,y) keep the
# legacy REPLACE behavior; mixing the two forms is an error. Unit-tests the
# pure helper parse_modules_arg so the modes are pinned independent of the CLI.
set -euo pipefail

python3 - <<'EOF'
import sys
sys.path.insert(0, '.')
from configure import parse_modules_arg

# --- REPLACE mode (all bare) — unchanged legacy behavior -------------------
sel, flags, deps, warns = parse_modules_arg("safety,mcp", {"core", "ui"}, {})
assert sel == {"core", "safety", "mcp"}, f"replace dropped ui + kept core: {sel}"
assert warns == [], f"clean replace warned: {warns}"

# --- DELTA add (all signed) — starts from current, unions the add ----------
sel, flags, deps, warns = parse_modules_arg("+mcp", {"core", "safety"}, {})
assert sel == {"core", "safety", "mcp"}, f"delta add: {sel}"

# --- DELTA remove ----------------------------------------------------------
sel, flags, deps, warns = parse_modules_arg("-safety", {"core", "safety", "mcp"}, {})
assert sel == {"core", "mcp"}, f"delta remove: {sel}"

# --- DELTA add + remove together -------------------------------------------
sel, flags, deps, warns = parse_modules_arg("+ui,-safety", {"core", "safety"}, {})
assert sel == {"core", "ui"}, f"delta add+remove: {sel}"

# --- MIXED forms are rejected ----------------------------------------------
try:
    parse_modules_arg("safety,+mcp", {"core"}, {})
    raise SystemExit("FAIL: mixed form did not raise")
except ValueError:
    pass

# --- Legacy id inside a +add still translates + emits a deprecation ---------
sel, flags, deps, warns = parse_modules_arg("+token-efficiency-pro", {"core"}, {})
assert "token-efficiency" in sel, f"legacy add not translated: {sel}"
assert flags.get("token-efficiency", {}).get("tier") == "pro", f"flag not set: {flags}"
assert any("token-efficiency-pro" in d for d in deps), f"no deprecation: {deps}"

# --- Unknown id (delta add) is warned + skipped, never added ----------------
sel, flags, deps, warns = parse_modules_arg("+bogus", {"core"}, {})
assert "bogus" not in sel, f"unknown id leaked into selected: {sel}"
assert any("bogus" in w for w in warns), f"unknown id not warned: {warns}"

# --- Unknown id (bare replace) is warned + skipped --------------------------
sel, flags, deps, warns = parse_modules_arg("bogus,safety", {"core"}, {})
assert sel == {"core", "safety"}, f"bogus leaked or core lost: {sel}"
assert any("bogus" in w for w in warns), f"bare unknown not warned: {warns}"

# --- Removing a required module is refused (core always kept) ---------------
sel, flags, deps, warns = parse_modules_arg("-core", {"core", "safety"}, {})
assert "core" in sel, f"required core was removed: {sel}"
assert any("core" in w for w in warns), f"-core not warned: {warns}"

# --- Bare sigil tokens (empty id) are skipped, not crash --------------------
sel, flags, deps, warns = parse_modules_arg("+", {"core"}, {})
assert sel == {"core"}, f"lone + sigil mishandled: {sel}"

print("PASS: parse_modules_arg replace/delta/mixed/legacy/unknown/required all correct")
EOF
