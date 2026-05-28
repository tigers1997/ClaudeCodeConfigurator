#!/usr/bin/env bash
# apt: a definitely-not-real package should return 1.
set -euo pipefail

LIB="$PWD/templates/safety/hooks/_lib/availability_check.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH (not a Debian/Ubuntu host)"; exit 0
fi

if bash -c "source '$LIB' && check_package_available apt definitely-not-a-real-package-xyz123"; then
  echo "FAIL: nonexistent pkg returned 0 (should be 1)"; exit 1
else
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "PASS: nonexistent pkg returned 1"
  else
    echo "FAIL: nonexistent pkg returned $rc (should be 1)"; exit 1
  fi
fi
