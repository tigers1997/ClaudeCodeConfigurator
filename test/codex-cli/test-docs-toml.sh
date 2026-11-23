#!/usr/bin/env bash
# Every TOML block in the generated docs/codex-setup.md must parse and have the
# shape Codex accepts today: the Azure provider block as Microsoft's guide shows
# it, wire_api "responses" (the only valid value), and profiles as overlay files
# with top-level keys. The removed [profiles.*] form must never be generated.
# Needs tomllib (Python 3.11+); older interpreters skip.
set -euo pipefail

if ! python3 -c 'import tomllib' 2>/dev/null; then
    echo "SKIP: tomllib needs Python 3.11+; the generated TOML was not parsed"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for provider in openai azure; do
    python3 test/codex-cli/_make-config.py "$tmp/$provider.json" provider=$provider
    python3 configure.py --config "$tmp/$provider.json" --yes --dir "$tmp/$provider" >/dev/null
    python3 - "$tmp/$provider/docs/codex-setup.md" "$provider" <<'PY'
import re, sys, tomllib

text, provider = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]
blocks = [tomllib.loads(b) for b in re.findall(r"```toml\n(.*?)```", text, flags=re.S)]
assert len(blocks) == 3, f"expected config.toml + review + bulk blocks, got {len(blocks)}"
config, review, bulk = blocks

# Profiles are overlay files with top-level keys. A [profiles.*] table or a
# `profile = ` selector is what Codex 0.134.0 removed: --profile now errors on it.
for i, block in enumerate(blocks, 1):
    assert "profiles" not in block and "profile" not in block, f"block {i} uses the removed profile form"
assert review["model"] == "gpt-6.2-astra" and review["model_reasoning_effort"] == "high", review
assert bulk["model"] == "gpt-6.2-sol" and bulk["model_reasoning_effort"] == "medium", bulk

if provider == "azure":
    assert config["model_provider"] == "azure", config
    p = config["model_providers"]["azure"]
    assert p["wire_api"] == "responses", p                      # the only value Codex accepts
    assert p["env_key"] == "AZURE_OPENAI_API_KEY", p            # names a variable; never the key
    assert p["base_url"].startswith("https://") and p["base_url"].endswith("/openai/v1"), p
    assert "query_params" not in p, "the v1 endpoint needs no api-version"
    assert config["model"] == "gpt-6.2-sol", config             # a deployment name
else:
    assert "model_providers" not in config and "model_provider" not in config, config
    assert config["model"] == "gpt-6.2-sol", config
print(f"  {provider}: 3 TOML blocks parse and have the expected shape")
PY
done

# The names come from the form, not constants.
python3 test/codex-cli/_make-config.py "$tmp/c.json" provider=azure review_model=my-review-deploy bulk_model=my-bulk-deploy effort=medium
python3 configure.py --config "$tmp/c.json" --yes --dir "$tmp/custom" >/dev/null
grep -q 'model = "my-review-deploy"' "$tmp/custom/docs/codex-setup.md" \
    && grep -q 'model = "my-bulk-deploy"' "$tmp/custom/docs/codex-setup.md" \
    && grep -q 'model_reasoning_effort = "medium"' "$tmp/custom/docs/codex-setup.md" \
    || { echo "FAIL: custom model names did not reach docs/codex-setup.md"; exit 1; }

echo "PASS: generated Codex TOML parses, matches the Azure guide's shape, and never uses [profiles.*]"
