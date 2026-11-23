#!/usr/bin/env bash
# The workflow's first step decides, before any model runs, whether the key can be
# used safely. Its shell is extracted from the generated workflow and EXECUTED here
# under the situations that matter: no key; an OpenAI key; an Azure key with and
# without an endpoint and a model. The case that matters most is a key that is not
# an OpenAI key with no endpoint: the action would send it to api.openai.com.
# The step must also never print the key.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 test/codex-cli/_make-config.py "$tmp/c.json" holdout_ci=1
python3 configure.py --config "$tmp/c.json" --yes --dir "$tmp/p" >/dev/null

python3 - "$tmp/p/.github/workflows/holdout-review.yml" "$tmp/check.sh" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"- name: Check configuration\n(?:.*\n)*?( *)run: \|\n", text)
assert m, "no `Check configuration` step with a `run: |` body"
base = len(m.group(1))
body = []
for ln in text[m.end():].splitlines():
    if ln.strip() and len(ln) - len(ln.lstrip()) <= base:
        break
    body.append(ln[base + 2:] if ln.strip() else "")
open(sys.argv[2], "w", encoding="utf-8").write("#!/usr/bin/env bash\n" + "\n".join(body) + "\n")
PY

# case <name> <expected exit> <expected text or -> <key> <endpoint> <model>
check() {
    local name=$1 want=$2 text=$3 key=$4 endpoint=$5 model=$6 out rc=0
    out=$(env -i PATH="$PATH" CODEX_API_KEY="$key" ENDPOINT="$endpoint" MODEL="$model" bash "$tmp/check.sh" 2>&1) || rc=$?
    [ "$rc" = "$want" ] || { echo "FAIL: $name: exit $rc, wanted $want"; echo "$out"; exit 1; }
    if [ "$text" != "-" ]; then
        echo "$out" | grep -q -F -- "$text" || { echo "FAIL: $name: output lacks '$text'"; echo "$out"; exit 1; }
    fi
    if [ -n "$key" ] && echo "$out" | grep -q -F -- "$key"; then echo "FAIL: $name: the key was printed"; exit 1; fi
}

AZ="azure-style-key-0123456789abcdef"
check "no key"                           1 "CODEX_API_KEY is not set"            ""           ""                                 ""
check "OpenAI key, no endpoint"          0 -                                     "sk-test123" ""                                 ""
check "OpenAI project key"               0 -                                     "sk-proj-abc" ""                                ""
check "Azure key, endpoint and model"    0 -                                     "$AZ"        "https://x.example/openai/v1/responses" "gpt-deployment"
check "endpoint without a model"         1 "CODEX_REVIEW_MODEL is not"           "$AZ"        "https://x.example/openai/v1/responses" ""
check "Azure key and NO endpoint"        1 "send it to api.openai.com"           "$AZ"        ""                                 ""
check "Azure key, model but no endpoint" 1 "send it to api.openai.com"           "$AZ"        ""                                 "gpt-deployment"

echo "PASS: the config check refuses a missing key, an endpoint without a model, and a non-OpenAI key with no endpoint, and never prints the key"
