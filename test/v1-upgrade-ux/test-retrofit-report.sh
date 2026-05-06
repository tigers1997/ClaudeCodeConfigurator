#!/usr/bin/env bash
# Retrofit REPORT.md should:
#   - split staged files into "Identical" (safe to drop) vs "Differs" (review)
#   - point at the shipped /retrofit skill (not the stale "Tier 3 future" line)
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Pre-populate the target with a CLAUDE.md (so collision strategy fires) and
# one safety hook with content matching what v2 ships, plus one with custom
# content the user "modified".
mkdir -p "$tmp/.claude/hooks"
echo "# placeholder" > "$tmp/CLAUDE.md"
cp templates/safety/hooks/scan-secrets.sh "$tmp/.claude/hooks/scan-secrets.sh"
echo "# user-modified content" > "$tmp/.claude/hooks/block-dangerous-bash.sh"

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

report="$tmp/.claude-retrofit/REPORT.md"
[ -f "$report" ] || { echo "FAIL: REPORT.md not generated"; exit 1; }

# Identical section should list scan-secrets.sh.
grep -q "## Skipped — identical to v2 (safe to drop)" "$report" \
    || { echo "FAIL: missing 'Skipped — identical' section header"; cat "$report"; exit 1; }
grep -q "scan-secrets.sh" "$report" \
    || { echo "FAIL: scan-secrets.sh not in report at all"; exit 1; }

# Differs section should list block-dangerous-bash.sh.
grep -q "## Skipped — differs from v2 (review)" "$report" \
    || { echo "FAIL: missing 'Skipped — differs' section header"; cat "$report"; exit 1; }
grep -q "block-dangerous-bash.sh" "$report" \
    || { echo "FAIL: block-dangerous-bash.sh not in report"; exit 1; }

# Stale "Tier 3 future" footnote should be gone.
! grep -q "Tier 3" "$report" \
    || { echo "FAIL: stale 'Tier 3' footnote still present"; cat "$report"; exit 1; }

# New footer should reference the shipped /retrofit skill.
grep -q "/retrofit" "$report" \
    || { echo "FAIL: footnote missing /retrofit pointer"; exit 1; }

echo "PASS: retrofit REPORT.md classifies staged files + footnote up to date"
