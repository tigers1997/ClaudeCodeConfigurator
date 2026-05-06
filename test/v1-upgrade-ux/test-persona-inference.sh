#!/usr/bin/env bash
# infer_persona scores each persona by Jaccard overlap of the module set
# (0.7) + flag-match ratio (0.3). Returns the closest match, or "custom"
# when no persona scores >= 0.5.
set -euo pipefail

python3 - <<'PY'
import sys; sys.path.insert(0, '.')
from configure import infer_persona

# Exact module match for solo-experienced + matching flags → solo-experienced.
got = infer_persona(
    {"core", "safety", "git-workflow", "commands", "mcp", "token-efficiency", "ui"},
    {"safety": {"lockdown": False, "slop_scan": True, "slop_scan_action": "warn"},
     "token-efficiency": {"tier": "pro"},
     "commands": {"subset": "rigorous"}},
)
assert got == "solo-experienced", f"expected solo-experienced, got {got}"

# Team modules (multi-agent + github-actions) → small-team.
got = infer_persona(
    {"core", "safety", "git-workflow", "commands", "mcp", "token-efficiency", "ui",
     "multi-agent", "github-actions"},
    {"safety": {"lockdown": False, "slop_scan": True, "slop_scan_action": "warn"},
     "token-efficiency": {"tier": "pro"},
     "commands": {"subset": "rigorous"}},
)
assert got == "small-team", f"expected small-team, got {got}"

# Library-author shape → library-author.
got = infer_persona(
    {"core", "safety", "git-workflow", "commands", "github-actions"},
    {"safety": {"lockdown": False, "slop_scan": True, "slop_scan_action": "warn"},
     "commands": {"subset": "full"}},
)
assert got == "library-author", f"expected library-author, got {got}"

# Solo-newer shape → solo-newer.
got = infer_persona(
    {"core", "safety", "git-workflow", "token-efficiency", "commands", "mcp"},
    {"safety": {"lockdown": False, "slop_scan": True, "slop_scan_action": "warn"},
     "token-efficiency": {"tier": "basic"},
     "commands": {"subset": "curated"}},
)
assert got == "solo-newer", f"expected solo-newer, got {got}"

# Idiosyncratic shape with no good match → custom.
got = infer_persona({"core", "experiments-memory"}, {})
assert got == "custom", f"expected custom for idiosyncratic shape, got {got}"

# Empty config → custom.
got = infer_persona(set(), {})
assert got == "custom", f"expected custom for empty config, got {got}"

print("PASS")
PY
