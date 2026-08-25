#!/usr/bin/env bash
# Stop hook — runs the typecheck / lint / test commands you configured during
# cc-configure intake. Reports results to Claude via
# hookSpecificOutput.additionalContext on the next turn; never blocks.
# (That output shape is officially supported as of Claude Code 2.1.163 —
# feedback that keeps the turn going without being labeled a hook error.)
#
# Skipping rules (silent, not reported):
#   1. Empty command — you blanked the field in the form (e.g., "I don't have
#      a typecheck setup"). Edit .claude-config.json or rerun cc-configure to
#      add one later.
#   2. First binary not on PATH at runtime — e.g., `uv` isn't installed yet
#      on this machine. Defensive guard so a missing tool doesn't generate
#      noise; the underlying intent of the check is still configured.
#   3. Stack manifest missing — e.g., `pnpm test` configured but no
#      package.json exists yet. Typical when the project is still in the
#      brainstorming/planning phase before any code lands. Mapping lives in
#      manifest_for() below; tools not in the map (tsc, pytest, ruff, …)
#      have no guard and run unconditionally.
#   4. Background work in flight — the Stop input (stdin JSON) carries a
#      `background_tasks` array on Claude Code 2.1.145+. Non-empty means the
#      session is paused waiting for that work to wake it back up, not done:
#      running checks now would race the background command, and the real
#      stop fires when it finishes. Scheduled `session_crons` do NOT skip —
#      future scheduled work doesn't make the current stop less final. On
#      older Claude Code the field is absent and the checks run as always.
#
# Customize the CHECKS block below if you want a different set of commands or
# labels. The placeholder values are populated from your cc-configure form
# answers, but the file is yours to edit freely after scaffolding.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR"

# Skipping rule 4: bail while background work is in flight (see header).
# Guarded stdin read so direct terminal invocation doesn't hang on `cat`.
INPUT=""
if [ ! -t 0 ]; then INPUT="$(cat)"; fi
BG_COUNT="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    print(len(json.load(sys.stdin).get("background_tasks") or []))
except Exception:
    print(0)
' 2>/dev/null || echo 0)"
if [ "$BG_COUNT" -gt 0 ]; then exit 0; fi

# label|command  or  label|command|service
#  - labels are display-only; commands come from cc-configure.
#  - leave the command empty (label|) to skip a check entirely.
#  - add a docker-compose service as a 3rd field to run that check INSIDE the
#    container (reuses your existing service): runs `docker compose exec -T
#    <service> <command>` if it's up, else `docker compose run --rm <service>
#    <command>`; skips silently if docker/compose or the service is absent.
#    Service names are single tokens; a containerized command can't contain `|`.
#    Example:  "test|pytest|backend"   "typecheck|pnpm typecheck|frontend"
CHECKS=(
  "typecheck|uv run mypy ."
  "lint|uv run ruff check"
  "test|uv run pytest"
)

# Map the first binary of a check command to the manifest file that signals
# "this stack has been scaffolded." Empty string means "no manifest guard;
# run the command and let it surface its own errors." Add entries as new
# stacks gain support — POSIX case keeps macOS bash 3.2 happy.
manifest_for() {
  case "$1" in
    pnpm|npm|yarn|bun)            echo "package.json" ;;
    uv|poetry|pip|pip3)           echo "pyproject.toml" ;;
    cargo|rustc)                  echo "Cargo.toml" ;;
    go)                           echo "go.mod" ;;
    bundle|gem)                   echo "Gemfile" ;;
    mvn)                          echo "pom.xml" ;;
    gradle|./gradlew)             echo "build.gradle" ;;
    *)                            echo "" ;;
  esac
}

# Echo a working `docker compose` invocation, or return non-zero when the
# docker compose v2 CLI isn't usable here (so container checks skip, fail-open).
compose() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
  echo "docker compose"
}

# Probe the compose CLI once (it's a daemon round-trip); container-bound checks
# below reuse $CC. Empty string ⇒ compose unusable ⇒ those checks skip.
CC="$(compose)" || CC=""

REPORT=""
for entry in "${CHECKS[@]}"; do
  label="${entry%%|*}"
  rest="${entry#*|}"

  # Optional 3rd field = compose service. An entry is container-bound iff it
  # has >=2 pipes AND its final field is a bare token (compose service names
  # match [A-Za-z0-9._-]+). Otherwise it's a host command — `cmd` is everything
  # after the first pipe, so host commands may still contain a literal `|`.
  pipes="$(printf '%s' "$entry" | tr -cd '|' | wc -c | tr -d ' ')"
  last="${entry##*|}"
  if [ "$pipes" -ge 2 ] && printf '%s' "$last" | grep -qxE '[A-Za-z0-9._-]+'; then
    service="$last"
    cmd="${rest%|*}"
  else
    service=""
    cmd="$rest"
  fi

  # Skip empty (user opted out of this check during intake).
  [ -z "$cmd" ] && continue

  if [ -z "$service" ]; then
    # --- HOST branch (unchanged) ---
    first="$(printf '%s' "$cmd" | awk '{print $1}')"
    if ! command -v "$first" >/dev/null 2>&1; then continue; fi
    manifest="$(manifest_for "$first")"
    if [ -n "$manifest" ] && [ ! -f "$manifest" ]; then continue; fi
    run_cmd="$cmd"
  else
    # --- CONTAINER branch ---
    [ -z "$CC" ] && { echo "[stop-check] ${label}: docker compose unavailable; skipping container check" >&2; continue; }
    if ! $CC config --services 2>/dev/null | grep -qxF "$service"; then
      echo "[stop-check] ${label}: compose service '${service}' not defined; skipping" >&2
      continue
    fi
    # -T on both: hooks run non-interactively, so disable PTY allocation (else
    # compose < v2.2.0 prints "input device is not a TTY" into the report).
    if $CC ps --status running --services 2>/dev/null | grep -qxF "$service"; then
      run_cmd="$CC exec -T ${service} ${cmd}"
    else
      run_cmd="$CC run --rm -T ${service} ${cmd}"
    fi
  fi

  out=$(eval "$run_cmd" 2>&1) && status=0 || status=$?
  if [ $status -eq 0 ]; then
    REPORT="${REPORT}[stop-check] ${label}: OK"$'\n'
  else
    tail=$(printf '%s' "$out" | tail -n 30)
    REPORT="${REPORT}[stop-check] ${label}: FAIL (exit ${status})"$'\n'"${tail}"$'\n---\n'
  fi
done

# Emit decision JSON so Claude sees the report on the next turn.
# jq is not preinstalled on macOS, Windows, or most Linux distros, and the
# unguarded `jq -n` this used to be dropped the entire report when it was
# missing: the checks ran, the hook exited 0, and Claude never learned that
# anything failed. Fall back to python3 (already required by the ui module),
# then to stderr — never silently.
if [ -n "$REPORT" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$REPORT" '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":$ctx}}'
  elif command -v python3 >/dev/null 2>&1; then
    CC_STOP_REPORT="$REPORT" python3 -c 'import json, os
print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop",
                  "additionalContext": os.environ["CC_STOP_REPORT"]}}))'
  else
    printf '[stop-run-checks] neither jq nor python3 found; the check report below is NOT reaching Claude.\n%s\n' "$REPORT" >&2
  fi
fi
exit 0
