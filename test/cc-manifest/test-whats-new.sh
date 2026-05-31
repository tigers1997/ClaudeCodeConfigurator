#!/usr/bin/env bash
# F7 (dogfood 2026-05-30): `cc-configure --whats-new` is READ-ONLY. It compares
# the project's .cc-manifest.json (written_by version + SHA) against the current
# configurator build and prints the CHANGELOG Unreleased delta, then exits —
# no scaffolding, no writes. Covers: up-to-date, no-manifest (+read-only proof),
# older-version (headlines), stale-SHA (commits-ahead).
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# A: freshly scaffolded by the current build -> same SHA -> "Up to date".
python3 configure.py --persona solo-experienced --yes --dir "$tmp/a" >/dev/null 2>&1
out=$(python3 configure.py --whats-new --dir "$tmp/a" 2>&1)
echo "$out" | grep -q "Up to date" \
    || { echo "FAIL: A expected 'Up to date'"; echo "$out"; exit 1; }

# B: no manifest -> graceful message, exit 0, and NOTHING written (read-only).
mkdir -p "$tmp/b"
out=$(python3 configure.py --whats-new --dir "$tmp/b" 2>&1)
echo "$out" | grep -q "No .claude/.cc-manifest.json" \
    || { echo "FAIL: B expected no-manifest message"; echo "$out"; exit 1; }
[ ! -e "$tmp/b/.claude" ] || { echo "FAIL: B created .claude/ (not read-only)"; exit 1; }
[ ! -e "$tmp/b/.claude-config.json" ] || { echo "FAIL: B wrote .claude-config.json (not read-only)"; exit 1; }

# C: older-version manifest, no SHA -> lists the Unreleased CHANGELOG headlines.
python3 configure.py --persona solo-experienced --yes --dir "$tmp/c" >/dev/null 2>&1
python3 -c "import json;p='$tmp/c/.claude/.cc-manifest.json';d=json.load(open(p));d['written_by']='cc-configure 2.5.0';d.pop('written_by_sha',None);json.dump(d,open(p,'w'))"
out=$(python3 configure.py --whats-new --dir "$tmp/c" 2>&1)
echo "$out" | grep -q "Unreleased changes a re-run would pick up" \
    || { echo "FAIL: C expected Unreleased headlines"; echo "$out"; exit 1; }

# D: stale (real older) SHA -> reports commits-ahead. Skipped on a shallow
# checkout where HEAD~1 isn't present (CI default fetch-depth=1).
python3 configure.py --persona solo-experienced --yes --dir "$tmp/d" >/dev/null 2>&1
oldsha=$(git rev-parse --short HEAD~1 2>/dev/null || echo "")
if [ -n "$oldsha" ]; then
    python3 -c "import json;p='$tmp/d/.claude/.cc-manifest.json';d=json.load(open(p));d['written_by_sha']='$oldsha';json.dump(d,open(p,'w'))"
    out=$(python3 configure.py --whats-new --dir "$tmp/d" 2>&1)
    echo "$out" | grep -qE "advanced [0-9]+ commit" \
        || { echo "FAIL: D expected commits-ahead line"; echo "$out"; exit 1; }
fi

echo "PASS: --whats-new up-to-date / no-manifest(read-only) / older-version headlines / stale-SHA ahead"
