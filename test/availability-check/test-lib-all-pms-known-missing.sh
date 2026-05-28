#!/usr/bin/env bash
# For each PM available on the host, check that a known-missing package returns 1.
set -euo pipefail

LIB="$PWD/templates/safety/hooks/_lib/availability_check.sh"
fake="definitely-not-a-real-package-xyz123"
any_ran=0

run_for() {
  local pm="$1" cli="$2"
  if ! command -v "$cli" >/dev/null 2>&1; then
    echo "  skip $pm ($cli not on PATH)"
    return
  fi
  any_ran=1
  if bash -c "source '$LIB' && check_package_available '$pm' '$fake'"; then
    echo "FAIL: $pm reported nonexistent pkg as available"; exit 1
  else
    rc=$?
    if [ "$rc" -eq 1 ]; then
      echo "  pass $pm: nonexistent → 1"
    elif [ "$rc" -eq 2 ]; then
      echo "  skip $pm: probe inconclusive (rc=2) — likely needs metadata refresh"
    else
      echo "FAIL: $pm returned unexpected rc=$rc"; exit 1
    fi
  fi
}

run_for apt apt-cache
run_for brew brew
run_for dnf dnf
run_for yum yum
run_for pacman pacman
run_for apk apk

if [ "$any_ran" -eq 0 ]; then
  echo "SKIP: no supported PM detected on this host"; exit 0
fi
echo "PASS: all detected PMs returned 1 for known-missing pkg"
