#!/usr/bin/env bash
# Every generated file must carry LF line endings on every platform.
#
# Path.write_text() opens in text mode with newline=None, which translates "\n"
# to os.linesep — so scaffolding from Windows wrote CRLF into all 13 hooks,
# claude-ctx, CLAUDE.md and settings.json. Harmless *on* Windows (Git Bash
# strips the CR), but the shebang then carried one, and the moment that
# .claude/ was committed and cloned on Linux/macOS every hook died with
# "bad interpreter: /usr/bin/env bash^M". Scaffolded output is meant to be
# committed and shared (see CLAUDE.md § Repo bootstrap), and `small-team` is a
# shipped persona, so this is a mixed-OS correctness bug, not cosmetics.
#
# This test is a no-op on Linux/macOS (os.linesep is already "\n"); it earns its
# keep on the Windows CI leg.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona small-team --yes --dir "$tmp" >/dev/null

python3 - "$tmp" <<'PY'
import sys
from pathlib import Path

target = Path(sys.argv[1])
offenders, checked = [], 0

for path in sorted(target.rglob("*")):
    if ".git" in path.parts:
        continue
    try:
        if not path.is_file():
            continue
        blob = path.read_bytes()
    except OSError:
        continue          # unreadable or not a regular file — nothing to assert
    checked += 1
    crlf = blob.count(b"\r\n")
    if crlf:
        offenders.append((path.relative_to(target), crlf))

if offenders:
    print("FAIL: %d generated file(s) contain CRLF:" % len(offenders))
    for rel, n in offenders[:12]:
        print("  %s (%d CRLF)" % (rel, n))
    sys.exit(1)

if checked == 0:
    print("FAIL: scaffold produced no files to check")
    sys.exit(1)

# The shebang is the line that actually breaks execution on Linux/macOS.
shebangs = 0
for hook in sorted((target / ".claude" / "hooks").glob("*.sh")):
    first = hook.read_bytes().split(b"\n", 1)[0]
    if not first.startswith(b"#!"):
        print("FAIL: %s has no shebang" % hook.name)
        sys.exit(1)
    if first.endswith(b"\r"):
        print("FAIL: %s shebang carries a CR" % hook.name)
        sys.exit(1)
    shebangs += 1

if shebangs == 0:
    print("FAIL: no hook scripts found to check")
    sys.exit(1)

print("PASS: %d generated files are CRLF-free; %d hook shebangs clean" % (checked, shebangs))
PY
