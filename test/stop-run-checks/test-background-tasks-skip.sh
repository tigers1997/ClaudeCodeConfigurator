#!/usr/bin/env bash
# stop-run-checks.sh must skip the whole check run when the Stop-hook input
# on stdin reports in-flight background work (`background_tasks` non-empty,
# CC 2.1.145+): the session is paused waiting to be woken back up, not done,
# and running checks now would race the background command's output. The
# real stop fires when that work finishes — checks run then.
#
# Scheduled-only work (`session_crons`) must NOT gate: a cron firing later
# doesn't make the current stop less final. Empty/absent stdin (older CC,
# direct invocation) must keep the legacy run-everything behavior.
#
# Same marker-file technique as test-manifest-guard.sh: no dependency on
# parsing the hook's stdout.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Scaffold a real project so the template renders with cmd_* substitutions.
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

hook="$tmp/.claude/hooks/stop-run-checks.sh"
[ -x "$hook" ] || { echo "FAIL: hook not scaffolded at $hook"; exit 1; }

# Fake pnpm that leaves a marker file when invoked.
fakebin="$tmp/bin"
mkdir -p "$fakebin"
marker="$tmp/pnpm-was-called"
cat > "$fakebin/pnpm" <<EOF
#!/usr/bin/env bash
touch "$marker"
exit 0
EOF
chmod +x "$fakebin/pnpm"

# Manifest present, so stdin is the only thing gating the run.
echo '{}' > "$tmp/package.json"

# --- case 1: in-flight background task → skip silently ---
printf '%s' '{"hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[{"id":"task-001","type":"shell","status":"running","description":"tail logs"}],"session_crons":[]}' \
  | CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin:$PATH" bash "$hook" >/dev/null 2>&1 || true
if [ -e "$marker" ]; then
    echo "FAIL: checks ran despite an in-flight background task"
    exit 1
fi

# --- case 2: crons scheduled, nothing in flight → checks must run ---
printf '%s' '{"hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[],"session_crons":[{"id":"cron-1","schedule":"0 9 * * *"}]}' \
  | CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin:$PATH" bash "$hook" >/dev/null 2>&1 || true
if [ ! -e "$marker" ]; then
    echo "FAIL: checks skipped on session_crons alone (only background_tasks should gate)"
    exit 1
fi
rm -f "$marker"

# --- case 3: empty stdin (pre-2.1.145 CC / direct invocation) → checks run ---
CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin:$PATH" bash "$hook" </dev/null >/dev/null 2>&1 || true
if [ ! -e "$marker" ]; then
    echo "FAIL: checks skipped with no stdin payload (back-compat broken)"
    exit 1
fi

echo "PASS: background_tasks gates the check run; crons / empty input do not"
