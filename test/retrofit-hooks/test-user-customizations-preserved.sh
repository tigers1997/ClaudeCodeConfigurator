#!/usr/bin/env bash
# Dedup must not destroy genuine user customizations. A user-added hook
# group with a different matcher (or different command, or different
# timeout) is structurally distinct from configurator-shipped ones and
# must survive a retrofit unchanged.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

# Inject three user customizations:
#   1. A wholly new hook group (different matcher than anything we ship)
#   2. A hook with same matcher as a shipped one but a different command
#   3. A timeout-tweaked duplicate of a shipped hook (different value)
python3 -c "
import json
p = '$tmp/.claude/settings.json'
data = json.load(open(p))
data['hooks'].setdefault('PreToolUse', []).extend([
    {
        'matcher': 'WebSearch',
        'hooks': [{'type': 'command', 'command': '/usr/local/bin/log-websearch.sh', 'timeout': 5}]
    },
    {
        'matcher': 'Bash',
        'hooks': [{'type': 'command', 'command': '/home/user/scripts/my-custom-bash-guard.sh', 'timeout': 10}]
    },
])
# Tweak the timeout of an existing shipped hook to simulate a customization
for group in data['hooks']['PreToolUse']:
    if group.get('matcher') == 'Bash' and 'block-dangerous-bash' in str(group):
        new_group = json.loads(json.dumps(group))
        new_group['hooks'][0]['timeout'] = 999  # user bumped the timeout
        data['hooks']['PreToolUse'].append(new_group)
        break
json.dump(data, open(p, 'w'), indent=2)
"

# Capture the user-added entries
before_user_websearch=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/settings.json'))
print(any(g.get('matcher') == 'WebSearch' for g in data['hooks']['PreToolUse']))
")
[ "$before_user_websearch" = "True" ] || { echo "FAIL: test setup didn't add WebSearch hook"; exit 1; }

# Run retrofit
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

# All three customizations must survive
after_user_websearch=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/settings.json'))
print(any(g.get('matcher') == 'WebSearch' for g in data['hooks']['PreToolUse']))
")
after_user_custom_bash=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/settings.json'))
print(any('my-custom-bash-guard' in str(g) for g in data['hooks']['PreToolUse']))
")
after_user_timeout=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/settings.json'))
print(any('block-dangerous-bash' in str(g) and any(h.get('timeout') == 999 for h in g.get('hooks', [])) for g in data['hooks']['PreToolUse']))
")

fail=0
[ "$after_user_websearch" = "True" ] || { echo "FAIL: WebSearch hook lost after retrofit"; fail=1; }
[ "$after_user_custom_bash" = "True" ] || { echo "FAIL: custom-bash-guard hook lost after retrofit"; fail=1; }
[ "$after_user_timeout" = "True" ] || { echo "FAIL: timeout=999 customization lost after retrofit"; fail=1; }

[ "$fail" -eq 0 ] || exit 1
echo "PASS: 3 user customizations (new matcher, different command, tweaked timeout) all preserved across retrofit"
