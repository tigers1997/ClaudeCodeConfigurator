#!/usr/bin/env bash
# Repeated cc-configure --retrofit on the same project must NOT accumulate
# duplicate hook entries. Demonstrates + guards against the dogfood-reported
# bug (configure.py:1149-1151 historically concatenated without dedup, so
# every retrofit re-appended the configurator's own hook set; after N
# retrofits each hook fired N+1 times).
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Initial scaffold (writes .claude/settings.json with the configurator's hooks)
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

# Count hook entries in each event after the initial scaffold
count_hooks() {
    local event="$1"
    python3 -c "
import json
data = json.load(open('$tmp/.claude/settings.json'))
print(len(data.get('hooks', {}).get('$event', [])))
"
}

initial_pretool=$(count_hooks PreToolUse)
initial_posttool=$(count_hooks PostToolUse)
initial_stop=$(count_hooks Stop)
initial_sessstart=$(count_hooks SessionStart)

# Three more retrofits — same persona, same target — should be no-ops for hooks.
for i in 1 2 3; do
    python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
done

after_pretool=$(count_hooks PreToolUse)
after_posttool=$(count_hooks PostToolUse)
after_stop=$(count_hooks Stop)
after_sessstart=$(count_hooks SessionStart)

fail=0
[ "$after_pretool" = "$initial_pretool" ] \
    || { echo "FAIL: PreToolUse: $initial_pretool → $after_pretool after 3 retrofits"; fail=1; }
[ "$after_posttool" = "$initial_posttool" ] \
    || { echo "FAIL: PostToolUse: $initial_posttool → $after_posttool after 3 retrofits"; fail=1; }
[ "$after_stop" = "$initial_stop" ] \
    || { echo "FAIL: Stop: $initial_stop → $after_stop after 3 retrofits"; fail=1; }
[ "$after_sessstart" = "$initial_sessstart" ] \
    || { echo "FAIL: SessionStart: $initial_sessstart → $after_sessstart after 3 retrofits"; fail=1; }

[ "$fail" -eq 0 ] || exit 1
echo "PASS: 3 retrofits don't duplicate hook entries (PreToolUse=$initial_pretool, PostToolUse=$initial_posttool, Stop=$initial_stop, SessionStart=$initial_sessstart, stable across retrofits)"
