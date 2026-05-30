#!/usr/bin/env bash
# F1 (dogfood 2026-05-30): when a prior scaffold shipped a hook as a STANDALONE
# matcher group and the new release ships it BUNDLED with a sibling in one
# group, deep_merge_settings must union them into a single matcher group with
# each command appearing once — not append a second group that double-fires the
# shared command. This is the exact 2.6.0 -> HEAD `safety` upgrade shape
# (block-dangerous-bash standalone -> [block-dangerous-bash, check-package-availability]).
set -euo pipefail

python3 - <<'EOF'
import sys
sys.path.insert(0, '.')
from configure import deep_merge_settings

B = "$CLAUDE_PROJECT_DIR/.claude/hooks/block-dangerous-bash.sh"
P = "$CLAUDE_PROJECT_DIR/.claude/hooks/check-package-availability.sh"
S = "$CLAUDE_PROJECT_DIR/.claude/hooks/scan-secrets.sh"

# existing = prior 2.6.0 scaffold: block-dangerous-bash as a STANDALONE Bash group
existing = {"hooks": {"PreToolUse": [
    {"matcher": "Bash", "hooks": [{"type": "command", "command": B, "timeout": 10}]},
    {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": S, "timeout": 10}]},
]}}

# new = current release: block-dangerous-bash BUNDLED with check-package-availability
new = {"hooks": {"PreToolUse": [
    {"matcher": "Bash", "hooks": [
        {"type": "command", "command": B, "timeout": 10},
        {"type": "command", "command": P, "timeout": 10},
    ]},
    {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": S, "timeout": 10}]},
]}}

merged, msg = deep_merge_settings(existing, new)
pre = merged["hooks"]["PreToolUse"]

def count_cmd(groups, needle):
    return sum(1 for g in groups for h in g.get("hooks", []) if needle in h.get("command", ""))

bash_groups = [g for g in pre if g.get("matcher") == "Bash"]
assert len(bash_groups) == 1, f"expected 1 Bash group, got {len(bash_groups)}: {pre}"

n_block = count_cmd(pre, "block-dangerous-bash")
assert n_block == 1, f"block-dangerous-bash should appear once, got {n_block}: {pre}"

n_pkg = count_cmd(pre, "check-package-availability")
assert n_pkg == 1, f"check-package-availability should be merged in once, got {n_pkg}: {pre}"

n_scan = count_cmd(pre, "scan-secrets")
assert n_scan == 1, f"scan-secrets should appear once, got {n_scan}: {pre}"

print("PASS: standalone+bundled same-matcher groups union into one; no command double-fires")
EOF
