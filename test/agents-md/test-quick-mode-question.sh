#!/usr/bin/env bash
# Quick mode's fourth question picks the harnesses. A saved choice must survive
# a re-run (the persona question replaces `selected` wholesale before this one
# is asked), Enter keeps it, 0 clears it, and unparseable input never drops it.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dir="$tmp/p"
mkdir -p "$dir"

selected() {
    python3 - "$dir/.claude-config.json" <<'PY'
import json, sys
sel = json.load(open(sys.argv[1]))["selected"]
print(" ".join(sorted(m for m in sel if m in ("agents-md", "gemini-cli"))))
PY
}
# Answers, in order: persona, project name, stack, HARNESSES, repo URL, license.
run() { printf '\n\n\n%s\n\n\n' "$1" | python3 configure.py --dir "$dir" 2>&1; }

out=$(run "2")
[ "$(selected)" = "agents-md gemini-cli" ] || { echo "FAIL: fresh pick 2 -> '$(selected)'"; exit 1; }
echo "$out" | grep -q 'Other AI harnesses besides Claude Code' || { echo "FAIL: harness question not asked"; exit 1; }
echo "$out" | grep -q '6 questions' || { echo "FAIL: banner does not say 6 questions"; exit 1; }

out=$(run "")
[ "$(selected)" = "agents-md gemini-cli" ] || { echo "FAIL: Enter dropped the saved choice -> '$(selected)'"; exit 1; }
echo "$out" | grep -q 'Enter = keep agents-md, gemini' || { echo "FAIL: prompt does not show the saved choice"; exit 1; }

run "zzz" >/dev/null
[ "$(selected)" = "agents-md gemini-cli" ] || { echo "FAIL: junk input dropped the saved choice -> '$(selected)'"; exit 1; }

run "1" >/dev/null
[ "$(selected)" = "agents-md" ] || { echo "FAIL: pick 1 -> '$(selected)'"; exit 1; }

run "1,2" >/dev/null
[ "$(selected)" = "agents-md gemini-cli" ] || { echo "FAIL: pick 1,2 -> '$(selected)'"; exit 1; }

run "0" >/dev/null
[ -z "$(selected)" ] || { echo "FAIL: pick 0 -> '$(selected)'"; exit 1; }

# A fresh dir with Enter everywhere is Claude-only and the prompt says so.
rm -rf "$dir"; mkdir -p "$dir"
out=$(run "")
[ -z "$(selected)" ] || { echo "FAIL: Enter on a fresh dir selected '$(selected)'"; exit 1; }
echo "$out" | grep -q 'pick \[Enter = none\]' || { echo "FAIL: fresh prompt hint wrong"; exit 1; }

# --harness answers the question: it is not asked, and the flag wins over the saved set.
rm -rf "$dir"; mkdir -p "$dir"
out=$(printf '\n\n\n\n\n' | python3 configure.py --harness gemini --dir "$dir" 2>&1)
echo "$out" | grep -q 'Other AI harnesses besides Claude Code' \
    && { echo "FAIL: question asked although --harness was given"; exit 1; }
[ "$(selected)" = "agents-md gemini-cli" ] || { echo "FAIL: --harness gemini in quick mode -> '$(selected)'"; exit 1; }

echo "PASS: quick-mode harness question keeps, replaces and clears the saved choice"
