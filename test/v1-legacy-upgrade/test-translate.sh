#!/usr/bin/env bash
# Verifies load_config translates legacy module IDs from a saved v1
# .claude-config.json (lockdown / token-efficiency-pro / commands-core /
# agents → modern IDs + flags), so --yes / --save-config / --dry-run paths
# don't carry stale IDs into v2 scaffolding. Mirrors --modules legacy
# handling so saved-config upgrades behave identically to CLI flags.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

cat > "$tmp/.claude-config.json" <<'EOF'
{
  "formValues": {"project_name": "v1-test", "stack_preset": "Python (uv)"},
  "selected": ["core", "commands-core", "agents", "lockdown", "token-efficiency-pro"]
}
EOF

python3 configure.py --save-config-only "$tmp/out.json" --dir "$tmp" >/dev/null

python3 - "$tmp/out.json" <<'PY'
import json, sys
cfg = json.loads(open(sys.argv[1]).read())

assert cfg["schema_version"] == 2, f"schema_version={cfg['schema_version']}"

selected = set(cfg["selected"])
flags = cfg.get("module_flags", {})

for legacy in ("commands-core", "agents", "lockdown", "token-efficiency-pro"):
    assert legacy not in selected, f"legacy '{legacy}' still in selected: {sorted(selected)}"

for modern in ("commands", "safety", "token-efficiency"):
    assert modern in selected, f"'{modern}' missing from selected: {sorted(selected)}"

assert flags.get("commands", {}).get("subset") == "full", \
    f"commands.subset != 'full': {flags.get('commands')}"
assert flags.get("safety", {}).get("lockdown") is True, \
    f"safety.lockdown != True: {flags.get('safety')}"
assert flags.get("token-efficiency", {}).get("tier") == "pro", \
    f"token-efficiency.tier != 'pro': {flags.get('token-efficiency')}"
PY

echo "PASS: v1 saved-config legacy module IDs translated on load"
