#!/usr/bin/env bash
# Shared bash lib: emit a compact installed-version chip for the status line.
# Source with: . "$CLAUDE_PROJECT_DIR/.claude/hooks/_lib/detect_tool_versions.sh"
# Public API:
#   emit_version_chip   echoes "deb13 · pg17 · node20 · py3.13" (omits absent tools)

emit_version_chip() {
  local chips=()
  local sep="·"

  # OS chip — Linux /etc/os-release, macOS sw_vers fallback.
  local os_chip
  os_chip=$(_chip_os) || true
  [ -n "$os_chip" ] && chips+=("$os_chip")

  # pg_config → "pg<major>"
  if command -v pg_config >/dev/null 2>&1; then
    local maj
    maj=$(pg_config --version 2>/dev/null | awk '{print $2}' | cut -d. -f1)
    [ -n "$maj" ] && chips+=("pg${maj}")
  fi

  # node → "node<major>"
  if command -v node >/dev/null 2>&1; then
    local maj
    maj=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)
    [ -n "$maj" ] && chips+=("node${maj}")
  fi

  # python3 → "py<major>.<minor>"
  if command -v python3 >/dev/null 2>&1; then
    local ver
    ver=$(python3 -V 2>&1 | awk '{print $2}' | cut -d. -f1-2)
    [ -n "$ver" ] && chips+=("py${ver}")
  fi

  # docker → "docker<major>"
  if command -v docker >/dev/null 2>&1; then
    local maj
    maj=$(docker -v 2>/dev/null | awk '{print $3}' | cut -d. -f1)
    [ -n "$maj" ] && chips+=("docker${maj}")
  fi

  # Join with " · "
  local out=""
  local first=1
  local c
  for c in "${chips[@]}"; do
    if [ "$first" -eq 1 ]; then
      out="$c"
      first=0
    else
      out="$out $sep $c"
    fi
  done
  printf '%s' "$out"
}

_chip_os() {
  if [ -r /etc/os-release ]; then
    local id ver
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    ver="${VERSION_ID:-}"
    case "$id" in
      debian) printf 'deb%s' "${ver%%.*}" ;;
      ubuntu) printf 'ubuntu%s' "${ver%%.*}" ;;
      fedora) printf 'fedora%s' "${ver%%.*}" ;;
      arch)   printf 'arch' ;;
      alpine) printf 'alpine%s' "${ver%%.*}" ;;
      *)      printf '%s%s' "$id" "${ver%%.*}" ;;
    esac
    return 0
  fi
  if command -v sw_vers >/dev/null 2>&1; then
    local ver
    ver=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
    [ -n "$ver" ] && printf 'mac%s' "$ver"
    return 0
  fi
  return 1
}
