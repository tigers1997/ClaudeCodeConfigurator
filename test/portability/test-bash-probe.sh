#!/usr/bin/env bash
# Verify --check resolves bash by *running* it, not by trusting PATH.
#
# The regression: GitHub's windows-latest image ships the WSL launcher
# (System32/bash.exe) ahead of Git Bash on PATH. With no distro installed it
# exits non-zero and writes NOTHING to stderr, so `bash -n` reported all 16
# shipped .sh files as "bash syntax error:" with a blank message — while passing
# on a dev box where Git Bash wins PATH. A missing/broken bash must degrade to a
# single warning, never a wall of phantom errors.
#
# Also pins the reported path to forward slashes on every platform.
set -euo pipefail

BROKEN="templates/safety/hooks/zz-bash-probe-fixture.sh"
cleanup() { rm -f "$BROKEN"; }
trap cleanup EXIT

python3 - <<'EOF'
import importlib.util, os, subprocess, sys, tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("cfg", "configure.py")
cfg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cfg)

# The report path must exist, or a WARN would crash the summary.
assert hasattr(cfg, "yellow"), "yellow() missing — the WARN branch would crash"

# 1. A candidate that exits non-zero with empty stderr — the WSL-launcher shape
#    — must be rejected, not returned.
d = Path(tempfile.mkdtemp())
if os.name == "nt":
    fake = d / "fakebash.cmd"
    fake.write_text("@echo off\r\nexit /b 1\r\n", encoding="ascii")
else:
    fake = d / "fakebash"
    fake.write_text("#!/bin/sh\nexit 1\n")
    fake.chmod(0o755)

os.environ["CC_BASH"] = str(fake)
picked = cfg._find_bash()
os.environ.pop("CC_BASH")
assert picked != str(fake), "a bash that exits non-zero was accepted as usable"

# 2. Whatever it does pick must actually run.
if picked is not None:
    r = subprocess.run([picked, "-c", "echo ok"], capture_output=True, text=True)
    assert r.stdout.strip() == "ok", f"_find_bash returned a non-working bash: {picked}"

# 3. No bash at all: one warning, and the check still succeeds. The point is
#    that an *unavailable* validation is not the same as a *failing* one.
real = cfg._find_bash
cfg._find_bash = lambda: None
rc = cfg.run_check()
cfg._find_bash = real
assert rc == 0, "a missing bash must warn, not fail the check"

print("PASS: bash is probed by execution; missing bash warns instead of failing")
EOF

# 4. A genuine syntax error is still caught, reported with forward slashes, and
#    without bash echoing its own absolute path back at us.
printf 'if true; then\n  echo hi\n' > "$BROKEN"
out=$(python3 configure.py --check 2>&1 | grep "zz-bash-probe-fixture" || true)
cleanup

case "$out" in
  "") echo "FAIL: a broken .sh was not reported at all"; exit 1 ;;
esac
case "$out" in
  *'\'*) echo "FAIL: backslash in reported path: $out"; exit 1 ;;
esac
case "$out" in
  *"templates/safety/hooks/zz-bash-probe-fixture.sh"*) ;;
  *) echo "FAIL: unexpected path form: $out"; exit 1 ;;
esac
case "$out" in
  *"unexpected end of file"*) ;;
  *) echo "FAIL: bash diagnostic missing: $out"; exit 1 ;;
esac

echo "PASS: syntax errors still caught, reported platform-identically"
