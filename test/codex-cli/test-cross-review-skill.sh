#!/usr/bin/env bash
# Invariants of the /cross-review skill text. It tells Claude to run another
# vendor's agent over the user's code, so what it allows, what it forbids and
# what it tells Claude to say before running are pinned. (--check separately
# validates the frontmatter and the reserved-name list.)
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 configure.py --persona solo-experienced --yes --harness codex --dir "$tmp" >/dev/null
skill="$tmp/.claude/skills/cross-review/SKILL.md"

python3 - "$skill" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
fm = text.split("---")[1]
body = text.split("---", 2)[2]

assert re.search(r"^name: cross-review$", fm, re.M), "name must be cross-review"
tools = re.search(r"^allowed-tools: (.*)$", fm, re.M).group(1)
# Running Codex must stay behind the permission prompt: the skill may not pre-approve it.
assert "codex" not in tools and "cross-review.sh" not in tools, f"allowed-tools pre-approves the call: {tools}"
assert "Write" not in tools and "Edit" not in tools, "a review skill must not be able to edit files"
assert "Sends repository content" in fm, "the description must say that content leaves the machine"

# Data egress is stated before running, and the prompt is not to be worked around.
assert "Before running" in body and "~/.codex" in body and "let them decline" in body
assert "do not work around it" in body

# The script is the only way Codex is run, and failures are not retried with other flags.
assert ".claude/skills/cross-review/scripts/cross-review.sh $ARGUMENTS" in body
assert "Do not retry with different flags" in body and "Do not install it" in body

# Findings are verified before they reach the user, with a confidence floor.
assert "Check every finding before it reaches the user" in body and "below 7 out of 10" in body
assert "Make none unasked" in body

# It must never suggest a flag that lifts the sandbox.
for bad in ("--yolo", "--full-auto", "danger-full-access", "--dangerously-bypass", "workspace-write"):
    assert bad not in text, f"the skill mentions {bad}"
# No dangling pattern include: shipped skills cannot resolve `include _patterns/...`.
assert "include _patterns" not in text
print("PASS: /cross-review keeps Codex behind the permission prompt, states data egress, and verifies findings")
PY
