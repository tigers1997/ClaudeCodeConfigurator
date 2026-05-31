#!/usr/bin/env bash
# F2 Part B (dogfood 2026-05-30): when a saved config's persona has GAINED a
# module since the config was written, a `--config --yes` upgrade replays the
# saved `selected` verbatim and silently omits the new module. The configurator
# must emit a [ NOTICE ] naming the gained module(s) + the add command, without
# force-installing. The NOTICE must be suppressed when the user is actively
# curating (--modules / --persona) or on a fresh scaffold (no drift concept).
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# A saved schema-2 config whose persona is solo-experienced but whose `selected`
# predates that persona gaining `discipline-skills` (the real dogfood case).
cat > "$tmp/cfg.json" <<'JSON'
{
  "schema_version": 2,
  "persona": "solo-experienced",
  "module_flags": {"token-efficiency": {"tier": "pro"}, "commands": {"subset": "rigorous"}},
  "formValues": {"project_name": "drift-test", "stack_preset": "Python (uv)"},
  "selected": ["core", "safety", "git-workflow", "token-efficiency", "commands", "mcp", "ui"]
}
JSON

# 1) Natural upgrade: --config --yes --dry-run → NOTICE fires.
out=$(python3 configure.py --config "$tmp/cfg.json" --yes --dry-run --dir "$tmp/p1" 2>&1)
echo "$out" | grep -q "NOTICE" || { echo "FAIL: no NOTICE block"; echo "$out"; exit 1; }
echo "$out" | grep -q "gained" || { echo "FAIL: NOTICE doesn't say 'gained'"; echo "$out"; exit 1; }
echo "$out" | grep -q "discipline-skills" || { echo "FAIL: gained module not named"; echo "$out"; exit 1; }
echo "$out" | grep -q -- "--modules +discipline-skills" || { echo "FAIL: no add command shown"; echo "$out"; exit 1; }

# 2) Suppressed when the user is curating modules (--modules +x).
out2=$(python3 configure.py --config "$tmp/cfg.json" --yes --dry-run --dir "$tmp/p2" --modules +ui 2>&1)
echo "$out2" | grep -q "gained" && { echo "FAIL: NOTICE not suppressed under --modules"; echo "$out2"; exit 1; } || true

# 3) Suppressed under explicit --persona (it replaces selected wholesale).
out3=$(python3 configure.py --config "$tmp/cfg.json" --yes --dry-run --dir "$tmp/p3" --persona solo-experienced 2>&1)
echo "$out3" | grep -q "gained" && { echo "FAIL: NOTICE not suppressed under --persona"; echo "$out3"; exit 1; } || true

# 4) Suppressed on a fresh scaffold (no loaded config → no drift concept).
out4=$(python3 configure.py --persona solo-experienced --yes --dry-run --dir "$tmp/p4" 2>&1)
echo "$out4" | grep -q "gained" && { echo "FAIL: NOTICE fired on fresh scaffold"; echo "$out4"; exit 1; } || true

echo "PASS: persona-drift NOTICE fires on --config upgrade; suppressed for --modules/--persona/fresh"
