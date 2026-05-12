#!/usr/bin/env bash
# Rendered verify-setup SKILL.md must include the four bootstrap-state
# checks (#8 repo_url, #9 gitignore block, #10 nested .git, #11 scaffold
# committed). Guards against any of them being accidentally dropped by a
# future SKILL.md edit.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
sk="$tmp/.claude/skills/verify-setup/SKILL.md"
[ -f "$sk" ] || { echo "FAIL: SKILL.md not scaffolded at $sk"; exit 1; }

for header in \
    '^### 8\. Repo URL placeholder$' \
    '^### 9\. Claude Code gitignore block$' \
    '^### 10\. Nested `\.git/` discipline$' \
    '^### 11\. Scaffold committed$' ; do
    grep -qE "$header" "$sk" \
        || { echo "FAIL: header missing — '$header'"; exit 1; }
done

# allowed-tools must include the two new Bash() entries — without them
# the skill can't actually invoke `find` or `git ls-files` at runtime.
grep -qE '^allowed-tools:.*Bash\(find:\*\)' "$sk" \
    || { echo "FAIL: allowed-tools lacks Bash(find:*)"; grep '^allowed-tools' "$sk"; exit 1; }
grep -qE '^allowed-tools:.*Bash\(git:\*\)' "$sk" \
    || { echo "FAIL: allowed-tools lacks Bash(git:*)"; grep '^allowed-tools' "$sk"; exit 1; }

# Sentinel-string check for #9 — easy regression if the sentinel string
# in templates/core/.gitignore.append ever changes without updating this
# check.
grep -qE 'Claude Code ---' "$sk" \
    || { echo "FAIL: check #9 doesn't reference the sentinel comment"; exit 1; }

echo "PASS: verify-setup SKILL.md ships all 4 bootstrap-state checks + tooling"
