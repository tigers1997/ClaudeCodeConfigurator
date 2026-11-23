#!/usr/bin/env bash
# The codex harness: --harness, --codex-ci and the quick-mode follow-up that is
# only asked once Codex is picked. Existing harness numbers must not move.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

selected() { # <dir> -> sorted harness modules
    python3 - "$1/.claude-config.json" <<'PY'
import json, sys
sel = json.load(open(sys.argv[1]))["selected"]
print(" ".join(sorted(m for m in sel if m in ("agents-md", "gemini-cli", "codex-cli"))))
PY
}
flag() { # <dir> <flag> -> value of module_flags["codex-cli"][flag] or "unset"
    python3 - "$1/.claude-config.json" "$2" <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("module_flags", {}).get("codex-cli", {}).get(sys.argv[2], "unset"))
PY
}

# --harness codex pulls in agents-md; both together with gemini.
python3 configure.py --persona solo-experienced --yes --harness codex --dir "$tmp/a" >/dev/null
[ "$(selected "$tmp/a")" = "agents-md codex-cli" ] || { echo "FAIL: --harness codex -> '$(selected "$tmp/a")'"; exit 1; }
python3 configure.py --persona solo-experienced --yes --harness codex,gemini --dir "$tmp/b" >/dev/null
[ "$(selected "$tmp/b")" = "agents-md codex-cli gemini-cli" ] || { echo "FAIL: codex,gemini -> '$(selected "$tmp/b")'"; exit 1; }

# Replace semantics still hold: dropping codex removes it and its files' source module.
python3 configure.py --yes --harness agents-md --dir "$tmp/a" >/dev/null
[ "$(selected "$tmp/a")" = "agents-md" ] || { echo "FAIL: replacing codex left '$(selected "$tmp/a")'"; exit 1; }

# --codex-ci needs the codex harness: exit 2 and say how to fix it.
set +e
out=$(python3 configure.py --persona solo-experienced --yes --codex-ci --dir "$tmp/c" 2>&1); rc=$?
set -e
{ [ "$rc" = 2 ] && echo "$out" | grep -q -- '--harness codex'; } || { echo "FAIL: --codex-ci without codex should exit 2 (got $rc)"; echo "$out"; exit 1; }
[ ! -e "$tmp/c/.github" ] || { echo "FAIL: --codex-ci without codex still wrote files"; exit 1; }

# --codex-ci with the harness: the flag persists and the workflow is written.
python3 configure.py --persona solo-experienced --yes --harness codex --codex-ci --dir "$tmp/d" >/dev/null
[ "$(flag "$tmp/d" holdout_ci)" = "True" ] || { echo "FAIL: holdout_ci not persisted"; exit 1; }
[ -f "$tmp/d/.github/workflows/holdout-review.yml" ] && [ -f "$tmp/d/docs/holdout-review.md" ] \
    || { echo "FAIL: --codex-ci did not write the workflow and its doc"; exit 1; }

# Quick mode: answers are persona, name, stack, HARNESSES, [codex follow-up], repo, license.
qm() { printf '%s' "$1" | python3 configure.py --dir "$2" 2>&1; }

out=$(qm $'\n\n\n3\nn\n\n\n' "$tmp/q1")
echo "$out" | grep -q 'Codex CLI (cross-vendor reviewer' || { echo "FAIL: Codex is not offered as option 3"; exit 1; }
echo "$out" | grep -q 'Also add the PR review workflow' || { echo "FAIL: follow-up not asked after picking Codex"; exit 1; }
[ "$(selected "$tmp/q1")" = "agents-md codex-cli" ] && [ "$(flag "$tmp/q1" holdout_ci)" = "False" ] \
    || { echo "FAIL: pick 3 + n -> '$(selected "$tmp/q1")' holdout_ci=$(flag "$tmp/q1" holdout_ci)"; exit 1; }

out=$(qm $'\n\n\n3\ny\n\n\n' "$tmp/q2")
[ "$(flag "$tmp/q2" holdout_ci)" = "True" ] || { echo "FAIL: 'y' did not enable holdout_ci"; exit 1; }
[ -f "$tmp/q2/.github/workflows/holdout-review.yml" ] || { echo "FAIL: workflow not written after 'y'"; exit 1; }

# A saved answer is the default on re-run: Enter keeps it, the prompt shows it.
out=$(qm $'\n\n\n\n\n\n\n' "$tmp/q2")
echo "$out" | grep -q 'Y/n' || { echo "FAIL: saved holdout_ci=True is not the follow-up default"; exit 1; }
[ "$(flag "$tmp/q2" holdout_ci)" = "True" ] && [ "$(selected "$tmp/q2")" = "agents-md codex-cli" ] \
    || { echo "FAIL: Enter on re-run dropped the saved Codex choice"; exit 1; }

# Not asked when Codex was not picked: gemini only is still six answers.
out=$(qm $'\n\n\n2\n\n\n' "$tmp/q3")
echo "$out" | grep -q 'Also add the PR review workflow' && { echo "FAIL: follow-up asked without Codex"; exit 1; }
[ "$(selected "$tmp/q3")" = "agents-md gemini-cli" ] || { echo "FAIL: gemini pick moved: '$(selected "$tmp/q3")'"; exit 1; }

# --codex-ci pre-answers the follow-up in quick mode (no prompt).
out=$(printf '\n\n\n\n\n' | python3 configure.py --harness codex --codex-ci --dir "$tmp/q4" 2>&1)
echo "$out" | grep -q 'Also add the PR review workflow' && { echo "FAIL: follow-up asked although --codex-ci was given"; exit 1; }
[ "$(flag "$tmp/q4" holdout_ci)" = "True" ] || { echo "FAIL: --codex-ci in quick mode did not enable holdout_ci"; exit 1; }

echo "PASS: codex harness selection, --codex-ci and the quick-mode follow-up behave"
