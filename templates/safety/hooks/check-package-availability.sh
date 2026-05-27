#!/usr/bin/env bash
# PreToolUse hook: gate `<pm> install` commands against the host's configured repos.
# Hard-deny (exit 2) on missing pkg with a structured permissionDecisionReason on stderr.
# Fail-open posture: any uncertainty → exit 0 with stderr note.
set -uo pipefail

# Resolve lib paths relative to the installed hook location (.claude/hooks/check-package-availability.sh).
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AVAIL_LIB="${HOOK_DIR}/_lib/availability_check.sh"

# --- Read PreToolUse JSON from stdin ---
if ! command -v jq >/dev/null 2>&1; then
  echo "[check-package-availability] jq missing; install jq to enable availability checks" >&2
  exit 0
fi

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

# Empty command? nothing to gate.
[ -z "$cmd" ] && exit 0

# --- Bail on composite shell constructs ---
case "$cmd" in
  *'|'*|*'&&'*|*';'*|*'$('*|*'`'*)
    echo "[check-package-availability] composite shell expression; not gating" >&2
    exit 0
    ;;
esac

# --- Strip leading ENV=val prefixes ---
while [[ "$cmd" =~ ^[A-Z_][A-Z0-9_]*=[^[:space:]]+[[:space:]]+(.*)$ ]]; do
  cmd="${BASH_REMATCH[1]}"
done

# --- Strip optional sudo (with its own flags) ---
if [[ "$cmd" =~ ^sudo[[:space:]]+(.*)$ ]]; then
  cmd="${BASH_REMATCH[1]}"
  # Drop sudo flags like -E, -H, -u user
  while [[ "$cmd" =~ ^(-[A-Za-z]+|-u[[:space:]]+[^[:space:]]+)[[:space:]]+(.*)$ ]]; do
    cmd="${BASH_REMATCH[2]}"
  done
fi

# --- Split into tokens ---
# Bash word-splitting is intentional here.
# shellcheck disable=SC2206
tokens=($cmd)
[ "${#tokens[@]}" -ge 2 ] || exit 0  # need at least cmd + subcmd

bin="${tokens[0]}"
subcmd="${tokens[1]}"

# --- Match package manager + subcommand ---
pm=""
case "$bin" in
  apt|apt-get)
    case "$subcmd" in
      install|reinstall) pm=apt ;;
      *) exit 0 ;;
    esac
    ;;
  brew)
    case "$subcmd" in
      install|reinstall) pm=brew ;;
      *) exit 0 ;;
    esac
    ;;
  dnf)
    case "$subcmd" in
      install|reinstall|upgrade) pm=dnf ;;
      *) exit 0 ;;
    esac
    ;;
  yum)
    case "$subcmd" in
      install|reinstall|upgrade) pm=yum ;;
      *) exit 0 ;;
    esac
    ;;
  pacman)
    case "$subcmd" in
      -S|-Sy|-Syu) pm=pacman ;;
      *) exit 0 ;;
    esac
    ;;
  apk)
    case "$subcmd" in
      add) pm=apk ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

# At this point: pm is set, tokens[0]/tokens[1] are cmd/subcmd.
# Remaining tokens are flags + packages.
# For Task 5 (skeleton), we stop here — extracting packages comes in later tasks.
# Bail with stderr note so we know we got this far during testing.
echo "[check-package-availability] reached pm=$pm dispatch (parsing not yet implemented)" >&2
exit 0
