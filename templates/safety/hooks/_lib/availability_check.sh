#!/usr/bin/env bash
# Shared bash lib: package-availability probes.
# Source with: . "$CLAUDE_PROJECT_DIR/.claude/hooks/_lib/availability_check.sh"
# Public API:
#   detect_package_manager         echoes: apt|brew|dnf|yum|pacman|apk|unknown
#   check_package_available <pm> <pkg>
#                                   exit 0 if pkg in a configured repo
#                                   exit 1 if pkg NOT in any configured repo
#                                   exit 2 if pm unknown / probe inconclusive

detect_package_manager() {
  if command -v apt-cache >/dev/null 2>&1; then echo apt; return; fi
  if command -v brew >/dev/null 2>&1;       then echo brew; return; fi
  if command -v dnf >/dev/null 2>&1;        then echo dnf; return; fi
  if command -v yum >/dev/null 2>&1;        then echo yum; return; fi
  if command -v pacman >/dev/null 2>&1;     then echo pacman; return; fi
  if command -v apk >/dev/null 2>&1;        then echo apk; return; fi
  echo unknown
}

check_package_available() {
  local pm="$1" pkg="$2"
  case "$pm" in
    apt)    _check_apt    "$pkg" ;;
    *)      return 2 ;;
  esac
}

_check_apt() {
  local pkg="$1"
  command -v apt-cache >/dev/null 2>&1 || return 2
  apt-cache pkgnames "$pkg" 2>/dev/null | grep -qx "$pkg"
}
