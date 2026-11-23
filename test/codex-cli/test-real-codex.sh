#!/usr/bin/env bash
# The codex-cli module against the REAL Codex CLI. Every other fixture here runs a
# stub, which cannot see what the real binary does with the arguments, the TOML or
# stdin (a stub is how `cross-review.sh` shipped a call that hangs when its stdin is
# an open pipe). This renders the module's own docs and script and checks them
# against `codex` itself: no credentials, a throwaway HOME, and every case reads only
# what Codex prints in its first seconds (config errors, the session header), so a
# missing network or a 401 does not matter. See _real_codex_check.py for the cases.
#
# Skips when `codex` is not installed; with REQUIRE_REAL_TOOLS set a missing CLI is a
# failure instead (the `codex-real-cli` CI job sets it, so it cannot go green on
# nothing).
set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
    if [ -n "${REQUIRE_REAL_TOOLS:-}" ]; then
        echo "FAIL: REQUIRE_REAL_TOOLS is set and the codex CLI is not installed"
        exit 1
    fi
    echo "SKIP: the codex CLI is not installed; the module was not checked against the real binary"
    exit 0
fi

python3 test/codex-cli/_real_codex_check.py "$(command -v codex)"
