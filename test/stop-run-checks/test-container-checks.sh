#!/usr/bin/env bash
# F3: a CHECKS entry with a 3rd field (compose service) runs the check inside
# that service — `docker compose exec -T <svc>` when it's running, else
# `docker compose run --rm <svc>` — bypassing the host-PATH/manifest guards.
# Infra-not-ready (no docker compose / service undefined) skips silently; a
# non-zero container exit is reported as FAIL. A 2-field entry stays host-side
# and never touches docker. Uses a PATH-prepended `docker` stub (no real Docker).
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Scaffold a real project so the template renders with cmd_* substitutions.
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
hook="$tmp/.claude/hooks/stop-run-checks.sh"
[ -x "$hook" ] || { echo "FAIL: hook not scaffolded at $hook"; exit 1; }

# Make `test` container-bound (service=backend); blank the others so only it runs.
python3 - "$hook" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace('"typecheck|pnpm typecheck"', '"typecheck|"')
t = t.replace('"lint|pnpm lint"', '"lint|"')
t = t.replace('"test|pnpm test"', '"test|pytest|backend"')
p.write_text(t)
PY

# Fake docker: logs compose exec/run args to $DOCKER_LOG, touches $DOCKER_MARKER,
# exits $FAKE_EXIT. `compose version` honors $FAKE_NO_COMPOSE; `config --services`
# echoes $FAKE_SERVICES; `ps` echoes $FAKE_RUNNING.
fakebin="$tmp/bin"; mkdir -p "$fakebin"
cat > "$fakebin/docker" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "compose" ] || exit 0
shift
case "${1:-}" in
  version) [ -n "${FAKE_NO_COMPOSE:-}" ] && exit 1; exit 0 ;;
  config)  printf '%s\n' ${FAKE_SERVICES:-backend frontend}; exit 0 ;;
  ps)      [ -n "${FAKE_RUNNING:-}" ] && printf '%s\n' ${FAKE_RUNNING}; exit 0 ;;
  exec|run) printf '%s\n' "$*" >> "$DOCKER_LOG"; touch "$DOCKER_MARKER"; exit "${FAKE_EXIT:-0}" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$fakebin/docker"

export DOCKER_LOG="$tmp/docker.log" DOCKER_MARKER="$tmp/docker.marker"
run_hook() {  # extra env as KEY=VAL args; prints the hook's stdout (the report)
  rm -f "$DOCKER_LOG" "$DOCKER_MARKER"
  env "$@" CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin:$PATH" bash "$hook" </dev/null 2>/dev/null || true
}

# A: service defined + NOT running -> docker compose run --rm backend
run_hook FAKE_SERVICES="backend frontend" FAKE_RUNNING="" >/dev/null
grep -q "run --rm backend" "$DOCKER_LOG" \
  || { echo "FAIL A: expected 'run --rm backend'; log: $(cat "$DOCKER_LOG" 2>/dev/null)"; exit 1; }

# B: service running -> docker compose exec -T backend
run_hook FAKE_SERVICES="backend frontend" FAKE_RUNNING="backend" >/dev/null
grep -q "exec -T backend" "$DOCKER_LOG" \
  || { echo "FAIL B: expected 'exec -T backend'; log: $(cat "$DOCKER_LOG" 2>/dev/null)"; exit 1; }

# C: service NOT defined -> skip (no exec/run)
run_hook FAKE_SERVICES="frontend" FAKE_RUNNING="" >/dev/null
[ -e "$DOCKER_MARKER" ] && { echo "FAIL C: ran a container cmd for an undefined service"; exit 1; } || true

# D: docker compose plugin missing -> skip
run_hook FAKE_NO_COMPOSE=1 >/dev/null
[ -e "$DOCKER_MARKER" ] && { echo "FAIL D: ran a container cmd with no compose plugin"; exit 1; } || true

# E: container command exits non-zero -> reported as FAIL
report=$(run_hook FAKE_SERVICES="backend frontend" FAKE_RUNNING="backend" FAKE_EXIT=1)
printf '%s' "$report" | grep -q "FAIL" \
  || { echo "FAIL E: non-zero container check not reported; report: $report"; exit 1; }

# F: a 2-field entry stays host-side and never invokes docker
python3 - "$hook" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
p.write_text(t.replace('"test|pytest|backend"', '"test|hostonly"'))
PY
cat > "$fakebin/hostonly" <<EOF
#!/usr/bin/env bash
touch "$tmp/host-ran"
exit 0
EOF
chmod +x "$fakebin/hostonly"
run_hook FAKE_SERVICES="backend frontend" FAKE_RUNNING="backend" >/dev/null
[ -e "$tmp/host-ran" ] || { echo "FAIL F: 2-field host check did not run host-side"; exit 1; }
[ -e "$DOCKER_MARKER" ] && { echo "FAIL F: 2-field host check invoked docker"; exit 1; } || true

echo "PASS: container checks use exec/run by service state, skip when infra absent, report failures, and 2-field stays host-side"
