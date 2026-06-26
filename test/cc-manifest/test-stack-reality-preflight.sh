#!/usr/bin/env bash
# check_stack_reality() (dogfood F2) warns when a configured check command's
# stack manifest is absent from the project root — the same condition that makes
# stop-run-checks.sh silently skip at runtime (skip rule 3). It must:
#   1. stay SILENT when the manifest is present at root (matched stack)
#   2. stay SILENT when no configured command maps to a known manifest
#   3. WARN + name the subdir when the manifest lives one level down (monorepo)
#   4. add a container note when a compose/Dockerfile is present
#   5. WARN "can't run here" when the manifest is absent everywhere
set -euo pipefail

proj_root=$(pwd)
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Pass DIR + form-values JSON via env to dodge nested-quote hell.
run() {  # $1 = dir ; $2 = form_values JSON
  DIR="$1" FV="$2" python3 -c "
import os, json, sys; sys.path.insert(0, '$proj_root')
from configure import check_stack_reality
from pathlib import Path
print(json.dumps(check_stack_reality(Path(os.environ['DIR']), json.loads(os.environ['FV']))))
"
}

# 1. Matched stack (pnpm + root package.json) -> silent
d="$tmp/matched"; mkdir -p "$d"; touch "$d/package.json"
out=$(run "$d" '{"cmd_test":"pnpm test","cmd_lint":"pnpm lint"}')
[ "$out" = "[]" ] || { echo "FAIL: matched stack should be silent; got: $out"; exit 1; }

# 2. No mappable binary (bare tsc / pytest) -> silent
d="$tmp/nomap"; mkdir -p "$d"
out=$(run "$d" '{"cmd_typecheck":"tsc --noEmit","cmd_test":"pytest"}')
[ "$out" = "[]" ] || { echo "FAIL: unmappable binaries should be silent; got: $out"; exit 1; }

# 3. Monorepo: pnpm configured, package.json only in frontend/ -> warn + name subdir
d="$tmp/monorepo"; mkdir -p "$d/frontend"; touch "$d/frontend/package.json"
out=$(run "$d" '{"cmd_test":"pnpm test"}')
echo "$out" | grep -q "no package.json at the project root" \
  || { echo "FAIL: monorepo should warn about missing root package.json; got: $out"; exit 1; }
echo "$out" | grep -q "frontend/" \
  || { echo "FAIL: monorepo warning should name the subdir frontend/; got: $out"; exit 1; }

# 4. Containerized monorepo (the dogfood shape: pnpm config, no root package.json,
#    frontend/package.json, docker-compose.yml) -> warn + container no-op note
d="$tmp/container"; mkdir -p "$d/frontend"
touch "$d/frontend/package.json" "$d/docker-compose.yml"
out=$(run "$d" '{"cmd_typecheck":"pnpm typecheck","cmd_lint":"pnpm lint","cmd_test":"pnpm test","cmd_install":"pnpm install"}')
echo "$out" | grep -q "docker-compose.yml" \
  || { echo "FAIL: containerized project should get the container no-op note; got: $out"; exit 1; }

# 5. Manifest absent everywhere -> warn "can't run here"
d="$tmp/absent"; mkdir -p "$d"
out=$(run "$d" '{"cmd_test":"cargo test"}')
echo "$out" | grep -q "anywhere in the tree" \
  || { echo "FAIL: fully-absent manifest should warn can't-run; got: $out"; exit 1; }

echo "PASS: check_stack_reality warns on root-manifest mismatch, names subdirs, flags containers, silent when matched"
