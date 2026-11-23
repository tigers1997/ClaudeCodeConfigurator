#!/usr/bin/env bash
# The stack-type mechanism: a preset prefills answers AND turns a module on, and
# switching presets turns the old stack's module off again. Covers --stack
# parsing, its precedence against --modules / --harness, the quick-mode question
# (including a saved choice on re-run), and the --check rule for the registry.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
MS="Microsoft data & BI (Fabric / Power BI / Power Platform)"

sel() { # <dir> -> stack/agents modules in the saved config
    python3 - "$1/.claude-config.json" <<'PY'
import json, sys
sel = json.load(open(sys.argv[1]))["selected"]
print(" ".join(sorted(m for m in sel if m in ("stack-microsoft-data", "agents-md"))))
PY
}
fv() { # <dir> <key>
    python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['formValues'].get(sys.argv[2]))" "$1/.claude-config.json" "$2"
}

# --- pure functions ---------------------------------------------------------
python3 - <<'EOF'
import sys
sys.path.insert(0, ".")
import configure
from config_schema import STACK_PRESETS, STACK_SLUGS

MS = "Microsoft data & BI (Fabric / Power BI / Power Platform)"
# slugs and full names, any case, resolve; unknown is a ValueError that names the slugs
for slug, name in STACK_SLUGS.items():
    assert configure.resolve_stack_arg(slug) == name
    assert configure.resolve_stack_arg(name.upper()) == name
    assert name in STACK_PRESETS
try:
    configure.resolve_stack_arg("cobol")
except ValueError as e:
    assert "microsoft-data" in str(e) and "python-uv" in str(e), e
else:
    raise AssertionError("an unknown stack was accepted")

ex = configure.apply_stack_extras
base = {"core", "safety"}
on = ex(base, MS)
assert on == {"core", "safety", "stack-microsoft-data", "agents-md"}, on          # dependsOn pulled agents-md in
assert ex(on, MS) == on                                                            # idempotent
off = ex(on, "Go")
assert off == {"core", "safety", "agents-md"}, off                                 # stack module off, agents-md stays
assert ex(base, "Custom / keep current") == base and ex(base, None) == base       # no preset, no change
assert configure.STACK_MODULES == {"stack-microsoft-data"}, configure.STACK_MODULES

# The preset prefills the stack answers, the commands the Stop hook runs, and replaces web-app design text.
fv = configure.default_form_values()
fv["stack_preset"] = MS
configure.apply_stack_preset(fv)
assert fv["cmd_typecheck"] == "./scripts/validate.sh --changed models report"
assert fv["cmd_lint"] == "./scripts/validate.sh --changed repo solution"
assert fv["cmd_test"] == "./scripts/validate.sh --changed python"
assert "python" not in fv["language"].lower(), "the word would trigger Python-app plugin recommendations"
assert "NextAuth" not in fv["auth"] and "React" not in fv["state_mgmt"]
assert fv["mcp_ms_learn"] is True
# Every select the preset sets must be a value prompt_select keeps (a plain select resets anything outside its options).
from config_schema import FORM_SCHEMA
fields = {f["key"]: f for s in FORM_SCHEMA for f in s["fields"]}
for key in STACK_PRESETS[MS]:
    f = fields.get(key)
    if f and f["type"] == "select" and not f.get("allow_custom"):
        assert STACK_PRESETS[MS][key] in f["options"], f"{key}={STACK_PRESETS[MS][key]!r} is not one of its options"
print("  pure functions: slugs, extras, prefill")
EOF

# --- CLI ------------------------------------------------------------------------
python3 configure.py --persona solo-experienced --yes --stack microsoft-data --dir "$tmp/a" >/dev/null
[ "$(sel "$tmp/a")" = "agents-md stack-microsoft-data" ] || { echo "FAIL: --stack microsoft-data -> '$(sel "$tmp/a")'"; exit 1; }
[ "$(fv "$tmp/a" stack_preset)" = "$MS" ] || { echo "FAIL: the preset name was not saved"; exit 1; }

# full name, other case
python3 configure.py --persona solo-experienced --yes --stack "microsoft data & bi (fabric / power bi / power platform)" --dir "$tmp/b" >/dev/null
[ "$(sel "$tmp/b")" = "agents-md stack-microsoft-data" ] || { echo "FAIL: full-name --stack"; exit 1; }

# unknown: exit 2, the slugs are listed, nothing is written
set +e
out=$(python3 configure.py --stack cobol --yes --dir "$tmp/bad" 2>&1); rc=$?
set -e
{ [ "$rc" = 2 ] && echo "$out" | grep -q 'microsoft-data'; } || { echo "FAIL: unknown --stack should exit 2 and list slugs (got $rc)"; echo "$out"; exit 1; }
[ ! -e "$tmp/bad/.claude-config.json" ] || { echo "FAIL: a rejected --stack still wrote a config"; exit 1; }

# --stack wins over an explicit --modules (the stack's module is always present) ...
python3 configure.py --modules core,safety --stack microsoft-data --dir "$tmp/c" >/dev/null
[ "$(sel "$tmp/c")" = "agents-md stack-microsoft-data" ] || { echo "FAIL: --modules then --stack lost the stack module: '$(sel "$tmp/c")'"; exit 1; }
# ... and --harness claude-code cannot drop agents-md that the stack module needs.
python3 configure.py --persona solo-experienced --yes --stack microsoft-data --harness claude-code --dir "$tmp/d" >/dev/null
[ "$(sel "$tmp/d")" = "agents-md stack-microsoft-data" ] || { echo "FAIL: --harness claude-code broke the stack's dependency: '$(sel "$tmp/d")'"; exit 1; }

# Switching away removes the stack's module, keeps shared agents-md, and replaces the commands.
python3 configure.py --yes --stack node-ts --dir "$tmp/a" >/dev/null
[ "$(sel "$tmp/a")" = "agents-md" ] || { echo "FAIL: switching to node-ts left '$(sel "$tmp/a")'"; exit 1; }
[ "$(fv "$tmp/a" cmd_test)" = "pnpm test" ] || { echo "FAIL: node-ts did not restore the commands"; exit 1; }

# --- quick mode ---------------------------------------------------------------------
n=$(python3 -c "import sys;sys.path.insert(0,'.');from config_schema import STACK_PRESETS;print(list(STACK_PRESETS).index('$MS')+1)")
qm() { printf '%s' "$1" | python3 configure.py --dir "$2" 2>&1; }   # persona, name, STACK, harness, repo, license
out=$(qm $'\n\n'"$n"$'\n\n\n\n' "$tmp/q")
[ "$(sel "$tmp/q")" = "agents-md stack-microsoft-data" ] || { echo "FAIL: quick mode pick $n -> '$(sel "$tmp/q")'"; exit 1; }
echo "$out" | grep -q "$n) $MS" || { echo "FAIL: the Microsoft preset is not offered as option $n"; exit 1; }

# Re-run, Enter everywhere: the saved stack and its module survive.
out=$(qm $'\n\n\n\n\n\n' "$tmp/q")
[ "$(sel "$tmp/q")" = "agents-md stack-microsoft-data" ] || { echo "FAIL: Enter on re-run dropped the stack: '$(sel "$tmp/q")'"; exit 1; }
echo "$out" | grep -q "default=$n" || { echo "FAIL: the saved stack is not the prompt's default"; exit 1; }
# Pick Node: the module goes, shared infrastructure stays.
qm $'\n\n1\n\n\n\n' "$tmp/q" >/dev/null
[ "$(sel "$tmp/q")" = "agents-md" ] || { echo "FAIL: picking Node in quick mode left '$(sel "$tmp/q")'"; exit 1; }

# --stack answers the question, so quick mode does not ask it.
out=$(printf '\n\n\n\n\n' | python3 configure.py --stack microsoft-data --dir "$tmp/q2" 2>&1)
echo "$out" | grep -q 'Stack preset:' && { echo "FAIL: the stack question was asked although --stack was given"; exit 1; }
[ "$(sel "$tmp/q2")" = "agents-md stack-microsoft-data" ] || { echo "FAIL: --stack in quick mode -> '$(sel "$tmp/q2")'"; exit 1; }

# --- the registry rule in --check ------------------------------------------------------
python3 - <<'EOF'
import contextlib, io, sys
sys.path.insert(0, ".")
import configure

def check():
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = configure.run_check()
    return rc, buf.getvalue()

rc, out = check()
assert rc == 0, out
extras = configure.STACK_PRESET_EXTRAS
slugs = configure.STACK_SLUGS
good = dict(extras)
try:
    extras["No such preset"] = {"modules": ["stack-microsoft-data"]}
    extras["Go"] = {"modules": ["no-such-module"], "review_rules": "stack-microsoft-data/missing.md"}
    slugs["bogus"] = "Not a preset"
    rc, out = check()
    assert rc == 1, out
    assert "STACK_PRESET_EXTRAS[No such preset]: is not a key of STACK_PRESETS" in out, out
    assert "references unknown module: no-such-module" in out, out
    assert "review_rules fragment missing: templates/stack-microsoft-data/missing.md" in out, out
    assert "STACK_SLUGS[bogus]: names a preset that does not exist" in out, out
finally:
    extras.clear(); extras.update(good); slugs.pop("bogus", None)
rc, out = check()
assert rc == 0, out
print("  --check: bad extras entries and slugs are reported; the shipped registry passes")
EOF

echo "PASS: --stack, quick mode and the extras mechanism add and remove the stack's module and nothing else"
