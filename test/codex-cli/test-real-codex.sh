#!/usr/bin/env bash
# The codex-cli module against the REAL Codex CLI. Every other fixture here runs a
# stub, which cannot see what the real binary does with the arguments, the TOML or
# stdin (a stub is how `cross-review.sh` shipped a call that hangs when its stdin is
# an open pipe). This renders the module's own docs and script and checks them
# against `codex` itself: no credentials, a throwaway HOME, and every case reads only
# what Codex prints in its first seconds (config errors, the session header), so a
# missing network or a 401 does not matter. See _real_codex_check.py for the cases.
#
# Opt-in, because the required `check` job runs every test/codex-cli/test-*.sh and must
# not depend on whatever happens to be installed or reachable on a runner. It runs
# only with CC_REAL_CODEX=1, or REQUIRE_REAL_TOOLS=1 (the `codex-real-cli` CI job
# sets that), and then a missing CLI is a failure, so the job cannot go green on
# nothing.
set -euo pipefail

if [ -z "${REQUIRE_REAL_TOOLS:-}" ] && [ -z "${CC_REAL_CODEX:-}" ]; then
    echo "SKIP: set CC_REAL_CODEX=1 to run the codex-cli module against the real codex CLI"
    exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
    echo "FAIL: CC_REAL_CODEX or REQUIRE_REAL_TOOLS is set and the codex CLI is not installed"
    exit 1
fi

python3 test/codex-cli/_real_codex_check.py "$(command -v codex)"
