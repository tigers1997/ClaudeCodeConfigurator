#!/usr/bin/env bash
# --harness REPLACES the saved harness set and touches only the harness
# modules. It is case- and space-tolerant, rejects unknown ids with exit 2, and
# treats `claude-code` / `none` as "Claude Code only".
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# selected <config> -> the harness modules, sorted, space-separated
selected() {
    python3 - "$1" <<'PY'
import json, sys
sel = json.load(open(sys.argv[1]))["selected"]
print(" ".join(sorted(m for m in sel if m in ("agents-md", "gemini-cli"))))
PY
}

# Unknown id: exit 2, an [ ERROR ] line, and the known ids named.
set +e
out=$(python3 configure.py --harness bogus --yes --dir "$tmp/bad" 2>&1)
rc=$?
set -e
[ "$rc" = "2" ] || { echo "FAIL: unknown harness exited $rc, expected 2"; echo "$out"; exit 1; }
echo "$out" | grep -q 'unknown harness' || { echo "FAIL: no 'unknown harness' message"; echo "$out"; exit 1; }
echo "$out" | grep -q 'agents-md, gemini' || { echo "FAIL: known harnesses not listed"; echo "$out"; exit 1; }

# Case and whitespace tolerant; both ids; dependency satisfied.
python3 configure.py --persona solo-experienced --yes --harness " AGENTS-MD , Gemini " --dir "$tmp/ok" >/dev/null
[ "$(selected "$tmp/ok/.claude-config.json")" = "agents-md gemini-cli" ] \
    || { echo "FAIL: tolerant parse selected '$(selected "$tmp/ok/.claude-config.json")'"; exit 1; }

# Replace semantics: dropping gemini keeps agents-md.
python3 configure.py --yes --harness agents-md --dir "$tmp/ok" >/dev/null
[ "$(selected "$tmp/ok/.claude-config.json")" = "agents-md" ] \
    || { echo "FAIL: --harness agents-md left '$(selected "$tmp/ok/.claude-config.json")'"; exit 1; }

# `none` clears.
python3 configure.py --yes --harness none --dir "$tmp/ok" >/dev/null
[ -z "$(selected "$tmp/ok/.claude-config.json")" ] \
    || { echo "FAIL: --harness none left '$(selected "$tmp/ok/.claude-config.json")'"; exit 1; }

# Only harness modules change: --modules sets the base, --harness layers on top.
python3 configure.py --modules core,safety --harness gemini --dir "$tmp/mix" >/dev/null
python3 - "$tmp/mix/.claude-config.json" <<'PY'
import json, sys
sel = set(json.load(open(sys.argv[1]))["selected"])
assert sel == {"core", "safety", "agents-md", "gemini-cli"}, sorted(sel)
PY

echo "PASS: --harness parses tolerantly, replaces only the harness modules, and rejects unknown ids"
