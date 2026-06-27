#!/usr/bin/env bash
# check_stack_reality() (dogfood F2) warns when a configured check command's
# stack manifest is absent from the project root — the same condition that makes
# stop-run-checks.sh silently skip at runtime (skip rule 3). It must:
#   1. stay SILENT when the manifest is present at root (matched stack)
#   2. stay SILENT when no configured command maps to a known manifest
#   3. WARN + name the subdir when the manifest lives one level down (monorepo)
#   4. add a container note ONLY when a warned binary is absent from the host
#      PATH (toolchain lives in the container) and a compose/Dockerfile is present
#   4b. SUPPRESS the container note when the binary IS on the host (monorepo whose
#      compose file is only for backing services — the hooks run fine)
#   5. WARN "can't run here" when the manifest is absent everywhere
#   6. ignore cmd_install/build/dev (stop-run-checks runs only typecheck/lint/test)
#   7. survive a malformed quote in a check command (shlex guard)
set -euo pipefail

proj_root=$(pwd)
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Pass DIR + form-values JSON via env to dodge nested-quote hell. $3 picks the
# host-PATH stub: none = nothing installed, all = everything installed, else real.
run() {  # $1 = dir ; $2 = form_values JSON ; $3 = which mode (none|all|real)
  DIR="$1" FV="$2" WHICH="${3:-real}" python3 -c "
import os, json, sys; sys.path.insert(0, '$proj_root')
from configure import check_stack_reality
from pathlib import Path
wm = os.environ['WHICH']
if wm == 'none':
    which = lambda b: None                # nothing on the host PATH
elif wm == 'all':
    which = lambda b: '/usr/bin/' + b     # everything on the host PATH
else:
    which = None                          # real shutil.which
print(json.dumps(check_stack_reality(Path(os.environ['DIR']), json.loads(os.environ['FV']), which=which)))
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
out=$(run "$d" '{"cmd_test":"pnpm test"}' all)
echo "$out" | grep -q "no package.json at the project root" \
  || { echo "FAIL: monorepo should warn about missing root package.json; got: $out"; exit 1; }
echo "$out" | grep -q "frontend/" \
  || { echo "FAIL: monorepo warning should name the subdir frontend/; got: $out"; exit 1; }

# 4. Containerized + toolchain ABSENT from host (which=none) -> warn + container note
d="$tmp/container"; mkdir -p "$d/frontend"
touch "$d/frontend/package.json" "$d/docker-compose.yml"
out=$(run "$d" '{"cmd_typecheck":"pnpm typecheck","cmd_lint":"pnpm lint","cmd_test":"pnpm test"}' none)
echo "$out" | grep -q "docker compose exec" \
  || { echo "FAIL: containerized + toolchain-off-host should get the container note; got: $out"; exit 1; }
echo "$out" | grep -q "CHECKS entry" \
  || { echo "FAIL: container note should point at the CHECKS service field in stop-run-checks.sh; got: $out"; exit 1; }

# 4b. A1: same layout but toolchain IS on host (which=all) -> subdir warn, NO container note
out=$(run "$d" '{"cmd_typecheck":"pnpm typecheck","cmd_lint":"pnpm lint","cmd_test":"pnpm test"}' all)
echo "$out" | grep -q "no package.json at the project root" \
  || { echo "FAIL: subdir warning should still fire when toolchain on host; got: $out"; exit 1; }
echo "$out" | grep -q "docker compose exec" \
  && { echo "FAIL: container note must be SUPPRESSED when the binary is on the host PATH; got: $out"; exit 1; } || true

# 5. Manifest absent everywhere -> warn "can't run here"
d="$tmp/absent"; mkdir -p "$d"
out=$(run "$d" '{"cmd_test":"cargo test"}')
echo "$out" | grep -q "anywhere in the tree" \
  || { echo "FAIL: fully-absent manifest should warn can't-run; got: $out"; exit 1; }

# 6. cmd_install/build/dev are NOT scanned (stop-run-checks.sh runs only
#    typecheck/lint/test) — a missing manifest for install alone stays silent.
d="$tmp/installonly"; mkdir -p "$d"
out=$(run "$d" '{"cmd_install":"pnpm install"}')
[ "$out" = "[]" ] || { echo "FAIL: cmd_install alone must not warn (stop-run-checks never runs it); got: $out"; exit 1; }

# 7. Malformed quote in a check command must NOT crash (shlex guard) —
#    it degrades to a plain split and still extracts the first binary.
d="$tmp/badquote"; mkdir -p "$d/frontend"; touch "$d/frontend/package.json"
out=$(run "$d" "{\"cmd_test\":\"pnpm test --grep 'foo\"}" all)
echo "$out" | grep -q "no package.json at the project root" \
  || { echo "FAIL: malformed-quote cmd should degrade gracefully and still warn; got: $out"; exit 1; }

# 8. Path-like binary (./gradlew) present at root -> NOT off-host (it's a local
#    file, not a PATH binary), so the container note is suppressed even with a
#    Dockerfile/compose. shutil.which('./gradlew') always returns None; the gate
#    file-checks path-like binaries instead of trusting PATH. (which-mode is
#    irrelevant here — the path branch never calls which.)
d="$tmp/gradlew"; mkdir -p "$d/app"; touch "$d/app/build.gradle" "$d/gradlew" "$d/docker-compose.yml"
out=$(run "$d" '{"cmd_test":"./gradlew test"}' none)
echo "$out" | grep -q "no build.gradle at the project root" \
  || { echo "FAIL: gradlew monorepo should warn about missing root build.gradle; got: $out"; exit 1; }
echo "$out" | grep -q "docker compose exec" \
  && { echo "FAIL: container note must be suppressed when ./gradlew exists at root; got: $out"; exit 1; } || true

echo "PASS: check_stack_reality — root-mismatch warns, names subdirs, container note gated on host reachability (incl. path-like ./gradlew), stop-hook-key scope, survives malformed quotes, silent when matched"
