#!/usr/bin/env bash
# Saved configs from v2.3.x carry the old `git@github.com:user/repo.git`
# literal default. Treat it as "user didn't set this" so existing users
# get the same [TODO:] treatment on next re-run.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

cat > "$tmp/.claude-config.json" <<'JSON'
{
  "schema_version": 2,
  "persona": "solo-experienced",
  "formValues": {"repo_url": "git@github.com:user/repo.git", "project_name": "legacy-default"},
  "selected": ["core", "safety", "git-workflow", "commands", "mcp", "ui", "token-efficiency"]
}
JSON

out=$(python3 configure.py --yes --dir "$tmp" --config "$tmp/.claude-config.json" 2>&1)

echo "$out" | grep -qE "field=repo_url" \
    || { echo "FAIL: legacy literal not detected as unset"; echo "$out"; exit 1; }
grep -qE '^\*\*Repo:\*\* \[TODO:' "$tmp/CLAUDE.md" \
    || { echo "FAIL: CLAUDE.md still shows legacy literal"; grep '^\*\*Repo:' "$tmp/CLAUDE.md"; exit 1; }

echo "PASS: legacy literal default upgraded to [TODO:] on re-run"
