#!/usr/bin/env bash
# This repository runs the codex-cli module's holdout review on itself. The workflow
# and its two docs are the module's own output, so they must not drift from it: when
# the template changes, regenerate them (the failure message says how).
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 test/codex-cli/_make-config.py "$tmp/c.json" holdout_ci=1 cross_review=0 provider=azure review_model=gpt-6.2-astra
python3 configure.py --config "$tmp/c.json" --yes --dir "$tmp/p" >/dev/null

drift=0
for f in .github/workflows/holdout-review.yml docs/holdout-review.md docs/codex-setup.md; do
    if ! diff -q "$tmp/p/$f" "$f" >/dev/null 2>&1; then
        echo "FAIL: $f is not what the codex-cli module generates"
        diff "$tmp/p/$f" "$f" 2>&1 | head -12 || true
        drift=1
    fi
done
if [ "$drift" != 0 ]; then
    echo "Regenerate the copies:"
    echo "  python3 test/codex-cli/_make-config.py /tmp/c.json holdout_ci=1 cross_review=0 provider=azure review_model=gpt-6.2-astra"
    echo "  python3 configure.py --config /tmp/c.json --yes --dir /tmp/p"
    echo "  cp /tmp/p/.github/workflows/holdout-review.yml .github/workflows/ && cp /tmp/p/docs/holdout-review.md /tmp/p/docs/codex-setup.md docs/"
    exit 1
fi
echo "PASS: this repository's holdout workflow and its two docs are exactly what the codex-cli module generates"
