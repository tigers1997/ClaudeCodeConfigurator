#!/usr/bin/env bash
# End-to-end: scaffold → drift → hook alert → retrofit → hook silent.
# Proves all three components (manifest writer, SessionStart hook, mcp module
# schema patch) cooperate as designed in the spec.
set -euo pipefail
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# 1. Initial scaffold (solo-experienced includes mcp module)
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

manifest="$tmp/.claude/.cc-manifest.json"
hook="$tmp/.claude/hooks/sessionstart-drift-check.sh"
[ -f "$manifest" ] || { echo "FAIL: manifest not scaffolded"; exit 1; }
[ -x "$hook" ]    || { echo "FAIL: hook not scaffolded or not executable"; exit 1; }

# 2. Confirm hook is silent on a fresh scaffold (baseline == current)
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$hook" 2>&1)
[ -z "$out" ] || { echo "FAIL: hook reported drift on fresh scaffold: $out"; exit 1; }

# 3. Simulate the user adding a new MCP after scaffold (using Python for portability)
python3 - "$tmp/.mcp.json" <<'PYSCRIPT'
import sys, json
mcp_path = sys.argv[1]
with open(mcp_path, 'r') as f:
    data = json.load(f)
if 'mcpServers' not in data:
    data['mcpServers'] = {}
data['mcpServers']['shadcn'] = {"command": "npx", "args": ["shadcn@latest"]}
with open(mcp_path, 'w') as f:
    json.dump(data, f, indent=2)
PYSCRIPT

# 4. Hook now alerts
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$hook" 2>&1)
echo "$out" | grep -q "1 added (shadcn)" \
    || { echo "FAIL: hook didn't report shadcn addition: $out"; exit 1; }

# 5. User accepts drift by running retrofit
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
python3 - "$manifest" <<'PYSCRIPT'
import sys, json
manifest_path = sys.argv[1]
with open(manifest_path, 'r') as f:
    data = json.load(f)
if 'shadcn' not in data.get('mcp_servers', []):
    print("FAIL: retrofit didn't accept shadcn into manifest")
    print(f"mcp_servers: {data.get('mcp_servers', [])}")
    sys.exit(1)
PYSCRIPT

# 6. Hook is silent again
out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$hook" 2>&1)
[ -z "$out" ] || { echo "FAIL: hook still reports drift after retrofit-accept: $out"; exit 1; }

echo "PASS: full drift-monitor lifecycle (scaffold → drift → alert → retrofit → silent)"
