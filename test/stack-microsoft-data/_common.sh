# shellcheck shell=bash
# Shared helpers for the stack-microsoft-data tests. Sourced, not run: the file
# name starts with an underscore so the `test-*.sh` loops never pick it up.
# Tests run from the repository root.

FIX="$(pwd)/test/stack-microsoft-data/fixtures"

# scaffold DIR [configure args...]: the Microsoft stack into DIR (solo-experienced persona).
scaffold() {
    local d="$1"; shift
    python3 configure.py --persona solo-experienced --yes --stack microsoft-data --dir "$d" "$@" >/dev/null
}

# git_init DIR: commit everything, so --changed has a HEAD to compare against.
git_init() {
    git -C "$1" init -q -b main
    git -C "$1" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false add -A
    git -C "$1" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m base
}

# with_fixtures DIR: copy the committed Fabric and Power Platform fixtures into DIR.
with_fixtures() {
    mkdir -p "$1/fabric" "$1/power-platform"
    cp -r "$FIX/fabric/." "$1/fabric/"
    cp -r "$FIX/power-platform/." "$1/power-platform/"
}

# config_file OUT 'python statements setting fv (form values) and flags (module flags)'
# writes a .claude-config.json for the solo-experienced persona + the Microsoft stack.
config_file() {
    python3 - "$1" "$2" <<'PY'
import json, sys
sys.path.insert(0, ".")
import configure
out, code = sys.argv[1], sys.argv[2]
fv = configure.default_form_values()
fv["stack_preset"] = "Microsoft data & BI (Fabric / Power BI / Power Platform)"
configure.apply_stack_preset(fv)
mods, pflags = configure.pick_persona_modules("solo-experienced")
selected = configure.apply_stack_extras(set(mods), fv["stack_preset"])
flags = {k: dict(v) for k, v in pflags.items()}
exec(code)
json.dump({"schema_version": 2, "persona": "solo-experienced", "module_flags": flags,
           "formValues": fv, "selected": sorted(selected)}, open(out, "w"))
PY
}
