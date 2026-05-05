#!/usr/bin/env bash
# PostToolUse on Bash — truncate long stdout/stderr before Claude sees it.
# Full output is written to .claude/logs/ so Claude can `tail` it if needed.
# Cap via CLAUDE_BASH_MAX_LINES env (default 80).
set -eu

MAX_LINES="${CLAUDE_BASH_MAX_LINES:-80}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
LOG_DIR="$PROJECT_DIR/.claude/logs"
mkdir -p "$LOG_DIR"

INPUT="$(cat)"

python3 - "$INPUT" "$LOG_DIR" "$MAX_LINES" <<'PY'
import json, os, sys, time

raw = sys.argv[1]
log_dir = sys.argv[2]
max_lines = int(sys.argv[3])

try:
    data = json.loads(raw)
except Exception:
    print(raw, end="")
    sys.exit(0)

tr = data.get("toolResponse") or data.get("tool_response") or {}
stdout = tr.get("stdout", "") or ""
stderr = tr.get("stderr", "") or ""

out_lines = stdout.splitlines()
err_lines = stderr.splitlines()

if len(out_lines) + len(err_lines) <= max_lines:
    print(raw, end="")
    sys.exit(0)

ts = time.strftime("%Y%m%d-%H%M%S")
log_file = os.path.join(log_dir, f"bash-{ts}-{os.getpid()}.log")
with open(log_file, "w") as f:
    f.write("=== STDOUT ===\n")
    f.write(stdout)
    f.write("\n=== STDERR ===\n")
    f.write(stderr)

keep = max_lines // 2

def trunc(lines, keep, label):
    if len(lines) <= keep:
        return "\n".join(lines)
    omitted = len(lines) - keep
    return "\n".join(lines[:keep]) + f"\n... [truncated {omitted} {label} lines; full log: {log_file}]"

tr["stdout"] = trunc(out_lines, keep, "stdout") if out_lines else ""
tr["stderr"] = trunc(err_lines, keep, "stderr") if err_lines else ""

# Preserve whichever key the host used
if "toolResponse" in data:
    data["toolResponse"] = tr
else:
    data["tool_response"] = tr

print(json.dumps(data), end="")
PY
