#!/usr/bin/env bash
# apt: a known-present package should return 0.
set -euo pipefail

LIB="$PWD/templates/safety/hooks/_lib/availability_check.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
  echo "SKIP: apt-cache not on PATH (not a Debian/Ubuntu host)"; exit 0
fi

if bash -c "source '$LIB' && check_package_available apt bash"; then
  echo "PASS: 'bash' is reported available via apt"
else
  echo "FAIL: 'bash' should be in apt repo on this host"; exit 1
fi
