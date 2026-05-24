#!/usr/bin/env bash
# A user who upgraded across several pre-fix releases may have a settings.json
# with N duplicate hook entries already. On their NEXT retrofit, the new
# dedup logic must collapse the prior buildup back to 1 entry per group.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Initial scaffold
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

# Simulate prior-version buildup: manually duplicate every hook group 3 times.
python3 -c "
import json
p = '$tmp/.claude/settings.json'
data = json.load(open(p))
for event, groups in data.get('hooks', {}).items():
    data['hooks'][event] = groups * 4  # 1 + 3 dupes = 4 total
json.dump(data, open(p, 'w'), indent=2)
"

# Sanity check: file now has inflated counts
inflated_pretool=$(python3 -c "import json; print(len(json.load(open('$tmp/.claude/settings.json'))['hooks']['PreToolUse']))")
[ "$inflated_pretool" -gt 3 ] || { echo "FAIL: test setup didn't actually inflate"; exit 1; }

# One retrofit — should collapse the inflated counts back to the baseline.
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

healed_pretool=$(python3 -c "import json; print(len(json.load(open('$tmp/.claude/settings.json'))['hooks']['PreToolUse']))")
healed_posttool=$(python3 -c "import json; print(len(json.load(open('$tmp/.claude/settings.json'))['hooks']['PostToolUse']))")
healed_stop=$(python3 -c "import json; print(len(json.load(open('$tmp/.claude/settings.json'))['hooks']['Stop']))")
healed_sessstart=$(python3 -c "import json; print(len(json.load(open('$tmp/.claude/settings.json'))['hooks']['SessionStart']))")

fail=0
# Expected baseline counts come from a fresh solo-experienced scaffold.
expected_pretool=3
expected_posttool=3
expected_stop=1
expected_sessstart=4
[ "$healed_pretool" = "$expected_pretool" ] \
    || { echo "FAIL: PreToolUse: inflated to $inflated_pretool, healed to $healed_pretool (expected $expected_pretool)"; fail=1; }
[ "$healed_posttool" = "$expected_posttool" ] \
    || { echo "FAIL: PostToolUse: healed to $healed_posttool (expected $expected_posttool)"; fail=1; }
[ "$healed_stop" = "$expected_stop" ] \
    || { echo "FAIL: Stop: healed to $healed_stop (expected $expected_stop)"; fail=1; }
[ "$healed_sessstart" = "$expected_sessstart" ] \
    || { echo "FAIL: SessionStart: healed to $healed_sessstart (expected $expected_sessstart)"; fail=1; }

[ "$fail" -eq 0 ] || exit 1
echo "PASS: inflated $inflated_pretool entries collapsed to baseline $expected_pretool on next retrofit"
