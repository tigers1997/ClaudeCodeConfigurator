#!/usr/bin/env bash
# Stop hook — runs the typecheck / lint / test commands you configured during
# cc-configure intake. Reports FAILURES to Claude via
# hookSpecificOutput.additionalContext on the next turn; never blocks.
# (That output shape is officially supported as of Claude Code 2.1.163.)
#
# An all-clear run emits nothing at all — see the ANY_FAIL gate at the bottom.
# "Everything passed" is not actionable, and a Stop hook that says it on every
# single stop pays context for no signal. Only a failure has something to say.
# (Any additionalContext from a Stop hook continues the turn — that is what
# the field is for — so "lint: OK" on every stop meant an idle turn on every
# stop, up to Claude Code's 8-consecutive-continuation cap.)
#
# A failure is reported once. The Stop input carries `stop_hook_active`, true
# when this stop ends a turn that a Stop hook already continued. On that stop
# a still-red run goes out as a top-level `systemMessage` — shown to the user,
# does not continue the turn — instead of additionalContext, so Claude gets
# exactly one continuation to fix a failure and an unfixable one cannot loop.
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

# Read the Stop input once: skipping rule 4 (background_tasks) and the
# report-once gate (stop_hook_active) both come from it. Guarded stdin read so
# direct terminal invocation doesn't hang on `cat`. Two space-separated
# numbers; anything unparsable (or no python3) reads as "0 0": run the checks,
# treat this as a first stop.
INPUT=""
if [ ! -t 0 ]; then INPUT="$(cat)"; fi
STOP_INFO="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d.get("background_tasks") or []), 1 if d.get("stop_hook_active") else 0)
except Exception:
    print(0, 0)
' 2>/dev/null || echo "0 0")"
BG_COUNT="${STOP_INFO%% *}"
STOP_HOOK_ACTIVE="${STOP_INFO##* }"
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
  "typecheck|{{cmd_typecheck}}"
  "lint|{{cmd_lint}}"
  "test|{{cmd_test}}"
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
# Tracks whether anything actually failed. The report is built either way —
# passing lines are useful context *alongside* a failure — but it is only
# emitted when this flips. See the gate below the loop.
ANY_FAIL=0
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
    ANY_FAIL=1
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
#
# Gated on ANY_FAIL: a fully-passing run emits nothing. Reporting "lint: OK"
# back on every stop costs context on every turn and tells Claude nothing it
# can act on. Failures still carry the passing lines with them, so a real
# report keeps its full context.
#
# Gated again on STOP_HOOK_ACTIVE: on the stop that ends a hook-continued
# turn, Claude already had this report once and the checks are still red. A
# second additionalContext would only buy another turn of the same, so the
# report goes out as a top-level systemMessage instead — the user sees it,
# the turn ends.
if [ -n "$REPORT" ] && [ "$ANY_FAIL" -eq 1 ]; then
  if [ "$STOP_HOOK_ACTIVE" -eq 1 ]; then
    REPORT="[stop-run-checks] still red after the fix attempt; the turn ends here."$'\n'"$REPORT"
  fi
  if command -v jq >/dev/null 2>&1; then
    if [ "$STOP_HOOK_ACTIVE" -eq 1 ]; then
      jq -n --arg msg "$REPORT" '{"systemMessage":$msg}'
    else
      jq -n --arg ctx "$REPORT" '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":$ctx}}'
    fi
  elif command -v python3 >/dev/null 2>&1; then
    CC_STOP_REPORT="$REPORT" CC_STOP_HOOK_ACTIVE="$STOP_HOOK_ACTIVE" python3 -c 'import json, os
report = os.environ["CC_STOP_REPORT"]
if os.environ["CC_STOP_HOOK_ACTIVE"] == "1":
    print(json.dumps({"systemMessage": report}))
else:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop",
                      "additionalContext": report}}))'
  else
    printf '[stop-run-checks] neither jq nor python3 found; the check report below is NOT reaching Claude.\n%s\n' "$REPORT" >&2
  fi
fi
exit 0
