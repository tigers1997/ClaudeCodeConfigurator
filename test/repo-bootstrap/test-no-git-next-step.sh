#!/usr/bin/env bash
# [ NEXT STEPS ] must include the "no git repo here yet" nudge when the
# target directory lacks a .git/ subdir, and must NOT include it when one
# exists. Suppressed in --dry-run because the user isn't writing anything.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# --- case 1: fresh dir, no .git → nudge fires ---
out1=$(python3 configure.py --persona solo-experienced --yes --dir "$tmp" 2>&1)
echo "$out1" | grep -qE "No git repo here yet" \
    || { echo "FAIL: no-git nudge missing when .git/ absent"; echo "$out1" | sed -n '/NEXT STEPS/,/^$/p'; exit 1; }

# --- case 2: re-run with .git present → nudge absent ---
rm -rf "$tmp"
tmp=$(mktemp -d)
mkdir "$tmp/.git"
out2=$(python3 configure.py --persona solo-experienced --yes --dir "$tmp" 2>&1)
if echo "$out2" | grep -qE "No git repo here yet"; then
    echo "FAIL: no-git nudge fired despite .git/ present"
    echo "$out2" | sed -n '/NEXT STEPS/,/^$/p'
    exit 1
fi

# --- case 3: --dry-run on a fresh dir → nudge suppressed ---
rm -rf "$tmp"
tmp=$(mktemp -d)
out3=$(python3 configure.py --persona solo-experienced --yes --dry-run --dir "$tmp" 2>&1)
if echo "$out3" | grep -qE "No git repo here yet"; then
    echo "FAIL: no-git nudge fired in --dry-run"
    echo "$out3" | sed -n '/NEXT STEPS/,/^$/p'
    exit 1
fi

echo "PASS: no-git nudge fires only when scaffolding into a non-git target"
