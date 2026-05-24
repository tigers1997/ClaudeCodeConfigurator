#!/usr/bin/env bash
# The shipped LICENSE file matches the upstream MIT text and acknowledges
# Jesse Vincent's copyright. Also verifies README.md mentions the
# attribution under Acknowledgments.
set -euo pipefail

# LICENSE: copyright line + "MIT License" header
grep -q "^MIT License$" templates/discipline-skills/LICENSE \
    || { echo "FAIL: LICENSE missing MIT header"; exit 1; }
grep -q "Copyright (c) 2025 Jesse Vincent" templates/discipline-skills/LICENSE \
    || { echo "FAIL: LICENSE missing upstream copyright"; exit 1; }
grep -q "Permission is hereby granted" templates/discipline-skills/LICENSE \
    || { echo "FAIL: LICENSE missing standard MIT permission text"; exit 1; }

# README acknowledgment
grep -q "obra/superpowers" README.md \
    || { echo "FAIL: README missing obra/superpowers attribution"; exit 1; }
grep -q "Jesse Vincent" README.md \
    || { echo "FAIL: README missing Jesse Vincent acknowledgment"; exit 1; }

echo "PASS: LICENSE + README acknowledgment correctly attribute obra/superpowers"
