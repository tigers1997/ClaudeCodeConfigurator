#!/usr/bin/env bash
# F1 (dogfood 2026-06-26): a prior scaffold shipped the microbit-enforcer
# SessionStart marker-clear with NO matcher; the new release ships it with
# matcher "startup|clear". _merge_hook_groups keys by matcher, so without a
# migration None != "startup|clear" appends a 2nd group and leaves the old
# matcherless one firing on every source — re-negating the freeze-loss fix on
# every `cc-configure --retrofit`. deep_merge_settings must MIGRATE the matcher
# in place (collapse to one group), while preserving any user-added hook.
set -euo pipefail

python3 - <<'EOF'
import sys
sys.path.insert(0, '.')
from configure import deep_merge_settings

CLEAR = ('rm -f "$CLAUDE_PROJECT_DIR"/.claude/.frozen '
         '"$CLAUDE_PROJECT_DIR"/.claude/.guarded '
         '"$CLAUDE_PROJECT_DIR"/.claude/.careful || true')

# existing = prior scaffold: SessionStart marker-clear with NO matcher
existing = {"hooks": {"SessionStart": [
    {"hooks": [{"type": "command", "command": CLEAR, "timeout": 5}]},
]}}
# new = current release: same command, now scoped to startup|clear
new = {"hooks": {"SessionStart": [
    {"matcher": "startup|clear", "hooks": [{"type": "command", "command": CLEAR, "timeout": 5}]},
]}}

merged, _ = deep_merge_settings(existing, new)
ss = merged["hooks"]["SessionStart"]

assert len(ss) == 1, f"matcher migration should collapse to one SessionStart group, got {len(ss)}: {ss}"
assert ss[0].get("matcher") == "startup|clear", \
    f"surviving group must carry the startup|clear matcher; got {ss[0].get('matcher')!r}: {ss}"
n_clear = sum(1 for g in ss for h in g.get("hooks", []) if ".frozen" in h.get("command", ""))
assert n_clear == 1, f"marker-clear command should appear exactly once, got {n_clear}: {ss}"

# A matcherless group that ALSO holds a user command: the migration is
# per-command, so the configurator's marker-clear migrates OUT to startup|clear
# while the user's own hook stays put under the matcherless group.
existing2 = {"hooks": {"SessionStart": [
    {"hooks": [
        {"type": "command", "command": CLEAR, "timeout": 5},
        {"type": "command", "command": "echo my-own-hook", "timeout": 5},
    ]},
]}}
merged2, _ = deep_merge_settings(existing2, new)
ss2 = merged2["hooks"]["SessionStart"]
matcherless2 = [g for g in ss2 if g.get("matcher") is None]
assert any("my-own-hook" in h.get("command", "") for g in matcherless2 for h in g.get("hooks", [])), \
    f"a user's own SessionStart hook must be preserved across retrofit: {ss2}"
assert not any(".frozen" in h.get("command", "") for g in matcherless2 for h in g.get("hooks", [])), \
    f"the marker-clear must migrate OUT of the matcherless group (not duplicate): {ss2}"
assert sum(1 for g in ss2 for h in g.get("hooks", []) if ".frozen" in h.get("command", "")) == 1, \
    f"marker-clear should appear exactly once after migration: {ss2}"

# Deliberate same-command-under-multiple-matchers (the mcp drift-check ships
# under both startup and resume) must survive — both are valid placements in
# the new template, so neither is treated as stale.
DRIFT = '"$CLAUDE_PROJECT_DIR"/.claude/hooks/sessionstart-drift-check.sh'
two = {"hooks": {"SessionStart": [
    {"matcher": "startup", "hooks": [{"type": "command", "command": DRIFT}]},
    {"matcher": "resume", "hooks": [{"type": "command", "command": DRIFT}]},
]}}
merged3, _ = deep_merge_settings(two, two)
matchers3 = sorted(g.get("matcher") for g in merged3["hooks"]["SessionStart"])
assert matchers3 == ["resume", "startup"], \
    f"multi-matcher drift-check must keep both placements: {merged3['hooks']['SessionStart']}"

print("PASS: matcherless SessionStart marker-clear migrates to startup|clear on retrofit (no ghost group); user hooks + deliberate multi-matcher groups preserved")
EOF
