#!/usr/bin/env bash
# Custom status line for Claude Code.
# Wire in settings.json: { "statusLine": { "type": "command", "command": "/absolute/path/to/statusline.sh" } }
#
# Receives a JSON blob on stdin. Outputs a single formatted line.
# Format: <dir> | <branch> | <model> | ctx <n>% [ | effort <lvl> ] [ | think ]
#
# Uses one python3 invocation (not five) to keep per-render overhead low.
set -euo pipefail

# stdin → env var so the heredoc below stays stdin-free for the Python reader.
export CC_STATUSLINE_INPUT="$(cat)"

# Optional OS+tool-version chip from safety/_lib (silently absent when safety
# module isn't installed). Opt out by exporting CC_STATUSLINE_NO_VERSION_CHIP=1.
export CC_STATUSLINE_CHIP=""
if [ -z "${CC_STATUSLINE_NO_VERSION_CHIP:-}" ]; then
  __chip_lib="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/_lib/detect_tool_versions.sh"
  if [ -r "$__chip_lib" ]; then
    # shellcheck disable=SC1090
    CC_STATUSLINE_CHIP=$(. "$__chip_lib" && emit_version_chip 2>/dev/null) || CC_STATUSLINE_CHIP=""
    export CC_STATUSLINE_CHIP
  fi
fi

python3 <<'PY'
import json, os, subprocess
from pathlib import Path

try:
    data = json.loads(os.environ.get("CC_STATUSLINE_INPUT", "{}"))
except Exception:
    data = {}

model_blk = data.get("model") or {}
model = model_blk.get("display_name") or model_blk.get("id") or "?"
cwd = data.get("cwd") or ""
ctx_pct = ((data.get("usage") or {}).get("context") or {}).get("used_pct", "?")
# 2.1.119+: may arrive on stdin. Empty → hidden (older versions unchanged).
effort = (data.get("effort") or {}).get("level", "") or ""
thinking = bool((data.get("thinking") or {}).get("enabled"))

# Git branch + dirty marker. Silently empty when cwd isn't a git repo.
branch = ""
if cwd:
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "symbolic-ref", "--short", "HEAD"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0:
            branch = result.stdout.strip() or "detached"
            dirty = subprocess.run(
                ["git", "-C", cwd, "status", "--porcelain"],
                capture_output=True, text=True, timeout=2,
            )
            if dirty.returncode == 0 and dirty.stdout.strip():
                branch += "*"
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

dir_name = Path(cwd).name if cwd else Path.cwd().name

# ANSI.
D, CY, G, Y, R = "\033[2m", "\033[36m", "\033[32m", "\033[33m", "\033[0m"
sep = f" {D}|{R} "

parts = [
    f"{CY}{dir_name}{R}",
    f"{G}{branch or 'no-git'}{R}",
    f"{Y}{model}{R}",
    f"ctx {ctx_pct}%",
]
if effort:
    parts.append(f"effort {effort}")
if thinking:
    parts.append(f"{Y}think{R}")

chip = os.environ.get("CC_STATUSLINE_CHIP", "").strip()
if chip:
    parts.append(f"{D}{chip}{R}")

print(sep.join(parts), end="")
PY
