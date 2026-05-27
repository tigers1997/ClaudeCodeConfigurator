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

# --- Extract packages from remaining tokens ---
# Per-PM value-taking flag allowlist (next token is a value, skip both).
declare -a value_flags_apt=("-t" "--target-release" "-o" "--option" "--config-file")
declare -a value_flags_dnf=("--releasever")
declare -a value_flags_pacman=("--config" "--dbpath" "--root")
declare -a value_flags_apk=("--repository" "--keys-dir")

skip_next=0
declare -a pkgs=()
i=2  # tokens[0]=bin, tokens[1]=subcmd
while [ "$i" -lt "${#tokens[@]}" ]; do
  tok="${tokens[$i]}"
  i=$((i+1))

  if [ "$skip_next" -eq 1 ]; then
    skip_next=0
    continue
  fi

  # Skip flags (start with -); check for value-taking ones first.
  case "$tok" in
    -*=*) continue ;;  # --foo=bar; no extra token to skip
    -*)
      # Look up in PM-specific value-flag list.
      flag_list=()
      case "$pm" in
        apt) flag_list=("${value_flags_apt[@]}") ;;
        dnf|yum) flag_list=("${value_flags_dnf[@]}") ;;
        pacman) flag_list=("${value_flags_pacman[@]}") ;;
        apk) flag_list=("${value_flags_apk[@]}") ;;
      esac
      for vf in "${flag_list[@]}"; do
        if [ "$tok" = "$vf" ]; then
          skip_next=1
          break
        fi
      done
      continue
      ;;
  esac

  # Skip file installs (./, /, *.deb, *.rpm, *.apk).
  case "$tok" in
    ./*|/*) echo "[check-package-availability] file install in args; not gating" >&2; exit 0 ;;
    *.deb|*.rpm|*.apk) echo "[check-package-availability] local archive in args; not gating" >&2; exit 0 ;;
  esac

  # Skip globs / brace / vars (parser bailouts).
  case "$tok" in
    *'*'*|*'?'*) echo "[check-package-availability] glob in pkg name; not gating" >&2; exit 0 ;;
    *'{'*'}'*) echo "[check-package-availability] brace expansion; not gating" >&2; exit 0 ;;
    *'$'*) echo "[check-package-availability] shell var in pkg name; not gating" >&2; exit 0 ;;
  esac

  # Strip version pin: pkg=ver (apt/dnf) or pkg@ver (brew).
  case "$pm" in
    brew) tok="${tok%@*}" ;;
    *)    tok="${tok%=*}" ;;
  esac

  pkgs+=("$tok")
done

# Nothing to check? bail.
[ "${#pkgs[@]}" -eq 0 ] && exit 0

# --- Run availability checks ---
[ -f "$AVAIL_LIB" ] || { echo "[check-package-availability] lib not found at $AVAIL_LIB; not gating" >&2; exit 0; }
# shellcheck disable=SC1090
source "$AVAIL_LIB"

declare -a missing=()
for pkg in "${pkgs[@]}"; do
  if check_package_available "$pm" "$pkg"; then
    :  # available — continue
  else
    rc=$?
    if [ "$rc" -eq 1 ]; then
      missing+=("$pkg")
    else
      # rc=2 inconclusive (probe failure / unknown pm)
      echo "[check-package-availability] $pm probe inconclusive for '$pkg' (rc=$rc); not gating" >&2
      exit 0
    fi
  fi
done

# All available?
[ "${#missing[@]}" -eq 0 ] && exit 0

# --- DENY ---
# Denial format is finalized in Task 7. For now, minimal message.
{
  printf '[check-package-availability] DENIED\n\n'
  printf 'Command: %s\n' "$cmd"
  printf 'Package manager: %s\n' "$pm"
  printf 'Missing: %s\n' "$(IFS=,; echo "${missing[*]}")"
} >&2
exit 2
