#!/usr/bin/env bash
# check_codex_fields warns about codex_* answers that would write a broken or
# misleading docs/codex-setup.md, and stays silent on the defaults and on real
# Azure deployment names. The warning reaches [ MODULE WARNINGS ] but never
# blocks the scaffold.
set -euo pipefail

python3 - <<'EOF'
import sys
sys.path.insert(0, ".")
from configure import check_codex_fields, default_form_values

fv = default_form_values()
assert check_codex_fields(fv) == [], check_codex_fields(fv)

for ok in ("gpt-6.2-astra", "my-review-deploy", "gpt_6.2:sol", "org/model@v2", "A1"):
    assert check_codex_fields({**fv, "codex_review_model": ok}) == [], ok

bad_names = ["", "has space", 'quo"te', "new\nline", "-leading", "semi;colon", "back`tick", "$(x)"]
for bad in bad_names:
    w = check_codex_fields({**fv, "codex_bulk_model": bad})
    assert len(w) == 1 and "codex_bulk_model" in w[0], (bad, w)

w = check_codex_fields({**fv, "codex_provider": "bedrock"})
assert len(w) == 1 and "falls back to openai" in w[0], w
w = check_codex_fields({**fv, "codex_review_effort": "max"})
assert len(w) == 1 and "codex_review_effort" in w[0], w
print("  check_codex_fields: silent on good values, one warning per bad field")
EOF

# End to end: warns, still scaffolds, exits 0.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 test/codex-cli/_make-config.py "$tmp/c.json" 'review_model=bad name'
rc=0; out=$(python3 configure.py --config "$tmp/c.json" --yes --dir "$tmp/p" 2>&1) || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: a bad model name blocked the scaffold (exit $rc)"; exit 1; }
echo "$out" | grep -q 'MODULE WARNINGS' && echo "$out" | grep -q 'codex_review_model' \
    || { echo "FAIL: no [ MODULE WARNINGS ] entry for the bad model name"; echo "$out"; exit 1; }
[ -f "$tmp/p/docs/codex-setup.md" ] || { echo "FAIL: docs/codex-setup.md not written"; exit 1; }

echo "PASS: codex field validation warns without blocking"
