#!/usr/bin/env bash
# PreToolUse hook: gate `<pm> install` commands against the host's configured repos.
# Hard-deny (exit 2) on missing pkg with a structured permissionDecisionReason on stderr.
# Fail-open posture: any uncertainty → exit 0 with stderr note.
set -uo pipefail

# Fail-open posture: any uncaught error → exit 0 with stderr note. Never block on internal bug.
trap 'rc=$?; echo "[check-package-availability] internal error (rc=$rc); not gating" >&2; exit 0' ERR

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

declare -a missing=()
for pkg in "${pkgs[@]}"; do
  # Each probe bounded at 3s via timeout; lib is re-sourced inside the subshell.
  if timeout 3 bash -c '. "$1" && check_package_available "$2" "$3"' _ "$AVAIL_LIB" "$pm" "$pkg"; then
    :  # available — continue
  else
    rc=$?
    if [ "$rc" -eq 1 ]; then
      missing+=("$pkg")
    elif [ "$rc" -eq 124 ]; then
      echo "[check-package-availability] $pm probe timed out for '$pkg'; not gating" >&2
      exit 0
    else
      # rc=2 inconclusive (probe failure / unknown pm) or other non-zero
      echo "[check-package-availability] $pm probe inconclusive for '$pkg' (rc=$rc); not gating" >&2
      exit 0
    fi
  fi
done

# All available?
[ "${#missing[@]}" -eq 0 ] && exit 0

# --- DENY ---

# Sibling search: derive stem (drop trailing -<digits>) and run a per-PM lookup.
sibling_stem() {
  local pkg="$1"
  # postgresql-18 → postgresql
  # postgresql-client-18 → postgresql-client
  echo "${pkg%-[0-9]*}"
}

available_list_apt() {
  local stem="$1"
  apt-cache search --names-only "^${stem}(-[a-z]+)?-?[0-9]+$" 2>/dev/null \
    | awk '{print $1}' | head -n 8
}

available_list_dnf() {
  local stem="$1"
  dnf -q list available "${stem}*" 2>/dev/null \
    | awk 'NR>1{print $1}' | head -n 8
}

available_list_yum() {
  local stem="$1"
  yum -q list available "${stem}*" 2>/dev/null \
    | awk 'NR>1{print $1}' | head -n 8
}

available_list_pacman() {
  local stem="$1"
  pacman -Ss "^${stem}" 2>/dev/null \
    | awk '/^[a-z]/{split($1,a,"/"); print a[2]}' | head -n 8
}

available_list_apk() {
  local stem="$1"
  apk search -q "${stem}*" 2>/dev/null | head -n 8
}

# brew search is slow; emit hint instead.
available_list_brew() {
  echo "(try: brew search ${1})"
}

# Detected installed version line, only if relevant to the missing pkg family.
detected_version_for_pkg() {
  local pkg="$1"
  case "$pkg" in
    postgresql*|postgres*)
      command -v pg_config >/dev/null 2>&1 || return
      pg_config --version 2>/dev/null
      ;;
    nodejs|node)
      command -v node >/dev/null 2>&1 || return
      node -v 2>/dev/null
      ;;
    python3*|python-*)
      command -v python3 >/dev/null 2>&1 || return
      python3 -V 2>&1
      ;;
    docker*|docker-ce*)
      command -v docker >/dev/null 2>&1 || return
      docker -v 2>/dev/null
      ;;
  esac
}

{
  printf '[check-package-availability] DENIED\n\n'
  printf 'Command: %s\n' "$cmd"
  printf 'Package manager: %s\n' "$pm"
  printf 'Missing: %s\n' "$(IFS=,; echo "${missing[*]}")"

  # Sibling search: take stem from first missing pkg.
  stem=$(sibling_stem "${missing[0]}")
  fn="available_list_${pm}"
  printf '\nAvailable (related to "%s", up to 8):\n  ' "$stem"
  $fn "$stem" | tr '\n' ' '
  printf '\n'

  # Detected installed version (if any matches the missing pkg family).
  det=$(detected_version_for_pkg "${missing[0]}")
  if [ -n "$det" ]; then
    printf '\nDetected installed: %s\n' "$det"
  fi

  printf '\nTo proceed:\n'
  printf '  • Pick an available version above, OR\n'
  printf '  • Configure the upstream repo first (then re-run), OR\n'
  printf '  • Recheck the package name\n'

  # Stale-cache warning (apt only).
  if [ "$pm" = "apt" ]; then
    lists_dir="${APT_LISTS_DIR:-/var/lib/apt/lists}"
    if [ -d "$lists_dir" ]; then
      if mtime=$(stat -c %Y "$lists_dir" 2>/dev/null); then
        now=$(date +%s)
        age_days=$(( (now - mtime) / 86400 ))
        if [ "$age_days" -gt 7 ]; then
          printf '\n⚠ apt cache is %d days old; consider '\''apt update'\'' before trusting this denial\n' "$age_days"
        fi
      fi
    fi
  fi
} >&2

exit 2
