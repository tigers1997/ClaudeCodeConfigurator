#!/usr/bin/env bash
# Pro-tier token-efficiency: the rules body is folded into CLAUDE.md as
# H3 subsections under "## Token efficiency rules", and the standalone
# .claude/rules/_efficiency-core.md file is NOT emitted.
set -euo pipefail

target=$(mktemp -d)
python3 configure.py --persona small-team --yes --dir "$target" >/dev/null

claude_md="$target/CLAUDE.md"
[[ -f "$claude_md" ]] || { echo "FAIL: CLAUDE.md not generated at $claude_md"; exit 1; }

grep -q "^## Token efficiency rules$" "$claude_md" \
    || { echo "FAIL: '## Token efficiency rules' section missing"; exit 1; }

grep -q "^### Reading files$" "$claude_md" \
    || { echo "FAIL: '### Reading files' subsection missing (pro-tier body did not fold in)"; exit 1; }

grep -q "^### Running bash$" "$claude_md" \
    || { echo "FAIL: '### Running bash' subsection missing"; exit 1; }

grep -q "^### Subagents$" "$claude_md" \
    || { echo "FAIL: '### Subagents' subsection missing"; exit 1; }

[[ ! -f "$target/.claude/rules/_efficiency-core.md" ]] \
    || { echo "FAIL: stale .claude/rules/_efficiency-core.md still emitted"; exit 1; }

echo "PASS: pro-tier folds rules into CLAUDE.md; standalone file absent"
