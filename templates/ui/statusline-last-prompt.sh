#!/usr/bin/env bash
# Alternative status line — shows the last user prompt from the session transcript.
# To activate, swap the statusLine.command in .claude/settings.json from
#   "$CLAUDE_PROJECT_DIR"/.claude/hooks/statusline.sh
# to
#   "$CLAUDE_PROJECT_DIR"/.claude/hooks/statusline-last-prompt.sh
#
# Reads the stdin JSON, follows transcript_path, walks the JSONL in reverse,
# and returns the most recent real user prompt (skipping slash commands).
set -euo pipefail

# stdin -> env var, so the heredoc below stays stdin-free for the Python reader.
export CC_STATUSLINE_INPUT="$(cat)"

python3 <<'PY'
import json, os, re

try:
    data = json.loads(os.environ.get("CC_STATUSLINE_INPUT", "{}"))
except Exception:
    data = {}

path = data.get("transcript_path", "")
model_blk = data.get("model") or {}
model = model_blk.get("display_name") or model_blk.get("id") or "?"
ctx_pct = ((data.get("usage") or {}).get("context") or {}).get("used_pct", "?")

last_prompt = ""
if path and os.path.isfile(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
        for line in reversed(lines):
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get("type") != "user":
                continue
            msg = e.get("message") or {}
            if msg.get("role") != "user":
                continue
            c = msg.get("content")
            if not isinstance(c, str):
                continue
            c = c.strip()
            if not c or c.startswith("/"):
                continue
            last_prompt = c
            break
    except Exception:
        pass

last_prompt = re.sub(r"\s+", " ", last_prompt)
MAX = 80
if len(last_prompt) > MAX:
    last_prompt = last_prompt[:MAX - 1] + "…"

D, C, Y, R = "\033[2m", "\033[36m", "\033[33m", "\033[0m"
print(f"{C}{model}{R} {D}|{R} ctx {ctx_pct}% {D}|{R} {Y}last:{R} {last_prompt or '(none)'}", end="")
PY
