#!/usr/bin/env bash
# --harness codex writes the Codex setup doc and, by default, the /cross-review
# skill with its permission rules. The PR workflow is opt-in. No .codex/ is
# written: a repository cannot set a Codex provider, so shipping one would
# only mislead.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 configure.py --persona solo-experienced --yes --harness codex --dir "$tmp/a" >/dev/null
a="$tmp/a"
for f in AGENTS.md CLAUDE.md docs/codex-setup.md \
         .claude/skills/cross-review/SKILL.md .claude/skills/cross-review/scripts/cross-review.sh; do
    [ -f "$a/$f" ] || { echo "FAIL: --harness codex did not write $f"; exit 1; }
done
[ -x "$a/.claude/skills/cross-review/scripts/cross-review.sh" ] \
    || { echo "FAIL: cross-review.sh is not executable"; exit 1; }
[ "$(head -n1 "$a/CLAUDE.md")" = "@AGENTS.md" ] || { echo "FAIL: codex did not pull in the CLAUDE.md bridge"; exit 1; }
[ ! -e "$a/GEMINI.md" ] || { echo "FAIL: codex wrote GEMINI.md"; exit 1; }

# Opt-in pieces stay off by default.
[ ! -e "$a/.github/workflows/holdout-review.yml" ] || { echo "FAIL: holdout workflow written by default"; exit 1; }
[ ! -e "$a/docs/holdout-review.md" ] || { echo "FAIL: holdout doc written by default"; exit 1; }
[ ! -e "$a/.codex" ] || { echo "FAIL: a .codex/ directory was written; Codex ignores provider keys there"; exit 1; }

# Another vendor sees repository content: every Codex invocation must ask, and none may be pre-approved.
python3 - "$a/.claude/settings.json" <<'PY'
import json, sys
perms = json.load(open(sys.argv[1]))["permissions"]
need = ["Bash(codex exec:*)", "Bash(codex review:*)",
        "Bash(.claude/skills/cross-review/scripts/cross-review.sh:*)",
        "Bash(./.claude/skills/cross-review/scripts/cross-review.sh:*)"]
for rule in need:
    assert rule in perms.get("ask", []), f"{rule} is not an ask rule"
    assert rule not in perms.get("allow", []), f"{rule} is pre-approved"
PY

# Nothing unresolved, and the default branch reached the script as a quoted literal.
if grep -rn '{{' "$a/docs/codex-setup.md" "$a/.claude/skills/cross-review"; then
    echo "FAIL: unresolved placeholder"; exit 1
fi
grep -qx 'DEFAULT_BRANCH="main"' "$a/.claude/skills/cross-review/scripts/cross-review.sh" \
    || { echo "FAIL: default branch not substituted into cross-review.sh"; exit 1; }

# cross_review off: no skill, no rules. holdout_ci on: workflow and its doc.
python3 test/codex-cli/_make-config.py "$tmp/off.json" cross_review=0 holdout_ci=1
python3 configure.py --config "$tmp/off.json" --yes --dir "$tmp/b" >/dev/null
b="$tmp/b"
[ ! -e "$b/.claude/skills/cross-review" ] || { echo "FAIL: cross_review=0 still wrote the skill"; exit 1; }
python3 - "$b/.claude/settings.json" <<'PY'
import json, sys
ask = json.load(open(sys.argv[1]))["permissions"].get("ask", [])
assert not any("codex" in r or "cross-review" in r for r in ask), ask
PY
[ -f "$b/.github/workflows/holdout-review.yml" ] && [ -f "$b/docs/holdout-review.md" ] \
    || { echo "FAIL: holdout_ci=1 did not write the workflow and its doc"; exit 1; }
[ -f "$b/docs/codex-setup.md" ] || { echo "FAIL: setup doc missing when cross_review is off"; exit 1; }

echo "PASS: codex scaffold writes the setup doc and skill, keeps the workflow opt-in, and ships no .codex/"
