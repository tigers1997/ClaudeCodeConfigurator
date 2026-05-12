#!/usr/bin/env bash
# A user-supplied repo URL must NOT be turned into a [TODO:] — only the
# empty/legacy sentinel triggers stamping.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

cat > "$tmp/.claude-config.json" <<'JSON'
{
  "schema_version": 2,
  "persona": "solo-experienced",
  "formValues": {"repo_url": "https://github.com/owner/real.git", "project_name": "real-url"},
  "selected": ["core", "safety", "git-workflow", "commands", "mcp", "ui", "token-efficiency"]
}
JSON

out=$(python3 configure.py --yes --dir "$tmp" --config "$tmp/.claude-config.json" 2>&1)

if echo "$out" | grep -qE "field=repo_url"; then
    echo "FAIL: real URL was stamped with [TODO:]"; echo "$out"; exit 1
fi
grep -qE '^\*\*Repo:\*\* https://github\.com/owner/real\.git$' "$tmp/CLAUDE.md" \
    || { echo "FAIL: CLAUDE.md did not preserve real repo URL"; grep '^\*\*Repo:' "$tmp/CLAUDE.md"; exit 1; }

echo "PASS: explicit repo URL passes through to CLAUDE.md unchanged"
