#!/usr/bin/env bash
# detect_package_manager should return one of: apt|brew|dnf|yum|pacman|apk|unknown
set -euo pipefail

LIB="$PWD/templates/safety/hooks/_lib/availability_check.sh"
[ -f "$LIB" ] || { echo "FAIL: lib not found at $LIB"; exit 1; }

result=$(bash -c "source '$LIB' && detect_package_manager")
case "$result" in
  apt|brew|dnf|yum|pacman|apk|unknown) ;;
  *) echo "FAIL: detect_package_manager returned unexpected value: '$result'"; exit 1 ;;
esac
echo "PASS: detect_package_manager returned '$result'"
