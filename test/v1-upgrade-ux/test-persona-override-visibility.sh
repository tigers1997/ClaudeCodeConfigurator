#!/usr/bin/env bash
# When a persona overrides a flag the user had set in their saved config,
# the [ APPLIED ] block must surface the delta so the change isn't silent.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# User had safety.lockdown=true; solo-newer persona sets it false.
cat > "$tmp/.claude-config.json" <<JSON
{
  "schema_version": 2,
  "formValues": {"project_name": "test"},
  "selected": ["core", "safety"],
  "module_flags": {"safety": {"lockdown": true}}
}
JSON

out=$(python3 configure.py --persona solo-newer --yes --dry-run --dir "$tmp" 2>&1)
echo "$out" | grep -q "Persona overrides:" || { echo "FAIL: missing 'Persona overrides:' header"; echo "---OUTPUT---"; echo "$out"; exit 1; }
echo "$out" | grep -qE "safety\.lockdown.*True.*False" || { echo "FAIL: safety.lockdown override not shown in deltas"; echo "---OUTPUT---"; echo "$out"; exit 1; }
echo "PASS: persona-overridden flags surfaced in [ APPLIED ]"
