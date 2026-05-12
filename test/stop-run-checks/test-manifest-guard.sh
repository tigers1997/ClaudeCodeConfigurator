#!/usr/bin/env bash
# stop-run-checks.sh must silently skip when the configured stack's manifest
# (package.json / pyproject.toml / Cargo.toml / go.mod / Gemfile / pom.xml /
# build.gradle) hasn't been created yet. Cures noisy `pnpm test` (etc.)
# failures during the brainstorming/planning phase.
#
# Uses a marker file rather than parsing the hook's stdout, so the test
# doesn't depend on `jq` being installed (it is on CI's ubuntu-latest, but
# isn't guaranteed elsewhere).
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Scaffold a real project so the template renders with cmd_* substitutions.
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

hook="$tmp/.claude/hooks/stop-run-checks.sh"
[ -x "$hook" ] || { echo "FAIL: hook not scaffolded at $hook"; exit 1; }

grep -q 'pnpm' "$hook" \
    || { echo "FAIL: rendered hook doesn't include pnpm — preset drift?"; exit 1; }

# Fake pnpm that leaves a marker file when invoked. Shim PATH so this is
# the only `pnpm` the hook can find.
fakebin="$tmp/bin"
mkdir -p "$fakebin"
marker="$tmp/pnpm-was-called"
cat > "$fakebin/pnpm" <<EOF
#!/usr/bin/env bash
touch "$marker"
echo "pnpm: simulated failure" >&2
exit 7
EOF
chmod +x "$fakebin/pnpm"

# --- case 1: no package.json — manifest guard must skip silently ---
CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin:$PATH" bash "$hook" >/dev/null 2>&1 || true
if [ -e "$marker" ]; then
    echo "FAIL: hook invoked pnpm despite missing package.json"
    exit 1
fi

# --- case 2: package.json present — hook must run pnpm ---
echo '{}' > "$tmp/package.json"
CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin:$PATH" bash "$hook" >/dev/null 2>&1 || true
if [ ! -e "$marker" ]; then
    echo "FAIL: hook didn't invoke pnpm even with package.json present"
    exit 1
fi

echo "PASS: manifest guard skips silently without package.json, runs with it"
