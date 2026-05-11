#!/usr/bin/env bash
# Basic-tier token-efficiency: the form-driven bullets still render under
# "## Token efficiency rules" in CLAUDE.md, but the pro-tier H3 subsections
# do NOT appear, and no standalone rules file is emitted.
set -euo pipefail

target=$(mktemp -d)
python3 configure.py --persona solo-newer --yes --dir "$target" >/dev/null

claude_md="$target/CLAUDE.md"
[[ -f "$claude_md" ]] || { echo "FAIL: CLAUDE.md not generated at $claude_md"; exit 1; }

# Form bullets section still present (solo-newer opts into eff_* flags).
grep -q "^## Token efficiency rules$" "$claude_md" \
    || { echo "FAIL: '## Token efficiency rules' section missing (form bullets should still render)"; exit 1; }

# Pro-tier prose body should NOT appear.
if grep -q "^### Reading files$" "$claude_md"; then
    echo "FAIL: '### Reading files' present on basic tier (pro body leaked in)"
    exit 1
fi

if grep -q "^### Running bash$" "$claude_md"; then
    echo "FAIL: '### Running bash' present on basic tier (pro body leaked in)"
    exit 1
fi

[[ ! -f "$target/.claude/rules/_efficiency-core.md" ]] \
    || { echo "FAIL: stale .claude/rules/_efficiency-core.md emitted on basic tier"; exit 1; }

echo "PASS: basic-tier keeps form bullets only; no pro prose, no standalone file"
