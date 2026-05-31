#!/usr/bin/env bash
# F6 (dogfood 2026-05-30): the manifest records the configurator's OWN git
# short-SHA as `written_by_sha`, so two scaffolds produced by different
# between-release builds of the same static CC_VERSION are distinguishable
# (CC_VERSION alone can't tell "2.6.0" from "2.6.0 + unreleased commits").
# The field is always present: a short-SHA string in a git checkout, or JSON
# null otherwise — never absent (so readers like `--whats-new` can rely on it).
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null 2>&1

python3 - "$tmp" <<'PY'
import json, sys
d = json.load(open(sys.argv[1] + "/.claude/.cc-manifest.json"))
assert "written_by_sha" in d, f"written_by_sha absent from manifest: {sorted(d)}"
v = d["written_by_sha"]
assert v is None or isinstance(v, str), f"written_by_sha must be str|null, got {type(v).__name__}"
# This repo IS a git checkout, so we expect a non-empty short SHA here.
assert isinstance(v, str) and 6 <= len(v) <= 12, f"expected a short SHA, got {v!r}"
# written_by (the version string) is unchanged / still present.
assert d.get("written_by", "").startswith("cc-configure "), f"written_by malformed: {d.get('written_by')!r}"
PY

echo "PASS: F6 manifest records written_by_sha (well-typed short SHA alongside written_by)"
