#!/usr/bin/env bash
# repo_url default is now empty; normalize_conditional_placeholders should
# stamp a [TODO:] so [ PLACEHOLDERS ] fires and CLAUDE.md doesn't ship a
# fake repo URL.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

out=$(python3 configure.py --persona solo-experienced --yes --dir "$tmp" 2>&1)

echo "$out" | grep -qE "^\[ PLACEHOLDERS \]" \
    || { echo "FAIL: [ PLACEHOLDERS ] block missing"; echo "$out"; exit 1; }
echo "$out" | grep -qE "field=repo_url" \
    || { echo "FAIL: repo_url not flagged in [ PLACEHOLDERS ]"; echo "$out"; exit 1; }

grep -qE '^\*\*Repo:\*\* \[TODO:' "$tmp/CLAUDE.md" \
    || { echo "FAIL: CLAUDE.md **Repo:** line did not render [TODO:]"; grep '^\*\*Repo:' "$tmp/CLAUDE.md"; exit 1; }

echo "PASS: empty repo_url default produces [TODO:] + [ PLACEHOLDERS ] warning"
