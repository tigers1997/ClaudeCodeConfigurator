#!/usr/bin/env bash
# verify-setup check 19 (Codex setup, user scope) must survive SKILL.md edits.
# It exists for one trap: a ~/.codex/config.toml that still has [profiles.*]
# tables, which Codex 0.134.0 stopped reading and now errors on. The anchors pin
# the version, the replacement file form and the "missing profile file is not an
# error" warning that makes a typo look like success.
set -euo pipefail

skill="templates/commands/verify-setup/SKILL.md"
anchors=(
    "### 19. Codex setup (user scope)"
    "0.134.0"
    "[profiles."
    "profile ="
    "<name>.config.toml"
    "review.config.toml"
    "CODEX_API_KEY"
    "Codex profiles:"
    "Codex review profile:"
    "a typo in the file name looks like success"
)
for anchor in "${anchors[@]}"; do
    grep -F -q -- "$anchor" "$skill" \
        || { echo "FAIL: missing anchor in $skill: '$anchor'"; exit 1; }
done

# It reads user-level files with the tools the skill already has: no new Bash permission.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 configure.py --persona solo-newer --yes --dir "$tmp" >/dev/null
rendered="$tmp/.claude/skills/verify-setup/SKILL.md"
grep -q '^### 19\. Codex setup (user scope)$' "$rendered" || { echo "FAIL: rendered verify-setup lacks check 19"; exit 1; }
grep -E '^allowed-tools:' "$rendered" | grep -q 'codex' && { echo "FAIL: verify-setup gained a codex Bash permission"; exit 1; }

echo "PASS: verify-setup check 19 (Codex setup) anchors are present and add no tool permission"
