#!/usr/bin/env bash
# Security lint for the generated holdout-review workflow (rules in
# test/codex-cli/_workflow_lint.py). A workflow that hands a PR to a model
# while holding an API key fails in quiet ways, so the shape is pinned: only the
# `pull_request` trigger, same-repo PRs, least-privilege jobs, SHA-pinned
# actions, a read-only Codex that cannot reach the key, review rules taken from
# the base commit, and no attacker-controlled text in the prompt.
#
# The lint is only worth something if each rule can fail, so this also feeds it
# a mutation per rule and checks that the right problem is reported.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 test/codex-cli/_make-config.py "$tmp/c.json" holdout_ci=1
python3 configure.py --config "$tmp/c.json" --yes --dir "$tmp/p" >/dev/null

python3 - "$tmp/p/.github/workflows/holdout-review.yml" <<'EOF'
import sys
sys.path.insert(0, "test/codex-cli")
from _workflow_lint import lint

text = open(sys.argv[1], encoding="utf-8").read()
problems = lint(text)
assert problems == [], "\n".join(problems)
print("  shipped workflow: clean")

CODEX_SHA = "306c6a196a99dcc6582530c396a19d2672d5e9ec"
mutations = [
    ("pull_request_target trigger", lambda t: t.replace("on:\n  pull_request:\n", "on:\n  pull_request_target:\n"), "pull_request_target"),
    ("PR title in the prompt", lambda t: t.replace("You are the independent reviewer", "Title: ${{ github.event.pull_request.title }}\n            You are the independent reviewer"), "attacker-controlled `github.event.pull_request.title`"),
    ("PR branch name in the prompt", lambda t: t.replace("You are the independent reviewer", "Branch: ${{ github.head_ref }}\n            You are the independent reviewer"), "attacker-controlled `github.head_ref`"),
    ("unpinned action", lambda t: t.replace(CODEX_SHA, "v1"), "not pinned to a 40-character commit SHA"),
    ("safety-strategy unsafe", lambda t: t.replace("safety-strategy: drop-sudo", "safety-strategy: unsafe"), "safety-strategy must be drop-sudo"),
    ("workspace permission profile", lambda t: t.replace('permission-profile: ":read-only"', 'permission-profile: ":workspace"'), "permission-profile must be"),
    ("credentials persisted", lambda t: t.replace("persist-credentials: false", "persist-credentials: true"), "persist-credentials: false"),
    ("review job can write contents", lambda t: t.replace("    permissions:\n      contents: read\n", "    permissions:\n      contents: write\n"), "exactly `contents: read`"),
    ("no top-level permissions", lambda t: t.replace("permissions: {}\n", ""), "top-level `permissions: {}`"),
    ("fork guard removed", lambda t: t.replace("      github.event.pull_request.head.repo.full_name == github.repository\n", "      true\n"), "same-repository guard"),
    ("AGENTS.md loading left on", lambda t: t.replace("project_doc_max_bytes=0", "project_doc_max_bytes=1"), "AGENTS.md loading is not switched off"),
    ("rules read from the PR tree", lambda t: t.replace('git show "$BASE_SHA:AGENTS.md"', "cat AGENTS.md"), "not read from the base commit"),
    ("inline expansion in a run body", lambda t: t.replace("          # The rules come from the base commit,", "          echo \"${{ github.event.pull_request.number }}\"\n          # The rules come from the base commit,"), "expands ${{ }} inline"),
    ("secret echoed in a run body", lambda t: t.replace('echo "::error::Repository secret CODEX_API_KEY is not set (see docs/holdout-review.md)."', 'echo "${{ secrets.CODEX_API_KEY }}"'), "secret used outside an env/with mapping value"),
    ("secret handed to the comment job", lambda t: t.replace("          PR_NUMBER: ${{ github.event.pull_request.number }}", "          PR_NUMBER: ${{ github.event.pull_request.number }}\n          LEAK: ${{ secrets.CODEX_API_KEY }}"), "neither run Codex nor read secrets"),
    ("sandbox-off flag", lambda t: t.replace("codex-args: '[\"-c\", \"project_doc_max_bytes=0\"]'", "codex-args: '[\"--yolo\"]'"), "a flag that disables the sandbox"),
    ("no concurrency", lambda t: t.replace("concurrency:\n  group: holdout-review-${{ github.event.pull_request.number }}-${{ github.run_attempt }}\n  cancel-in-progress: true\n", ""), "concurrency group"),
    ("no timeout", lambda t: t.replace("    timeout-minutes: 20\n", ""), "no timeout"),
    ("endpoint from a variable only", lambda t: t.replace("secrets.CODEX_RESPONSES_ENDPOINT || vars.CODEX_RESPONSES_ENDPOINT", "vars.CODEX_RESPONSES_ENDPOINT"), "read from a secret first"),
    ("lookup trusts any bot", lambda t: t.replace("c.user.login === 'github-actions[bot]'", "c.user.type === 'Bot'"), "match the posting bot"),
    ("marker anywhere in the body", lambda t: t.replace("c.body.startsWith(marker)", "c.body.includes(marker)"), "match the posting bot"),
    ("VERDICT not neutralised", lambda t: t.replace(".replace(/VERDICT:/gi, 'VERDICT\\u200b:')", ""), "neutralise `VERDICT:`"),
    ("stale review published", lambda t: t.replace("github.rest.pulls.get", "github.rest.pulls.list"), "head has moved on"),
    ("key-shape guard removed", lambda t: t.replace('case "$CODEX_API_KEY" in', 'case "$NOT_THE_KEY" in'), "key-shape guard"),
    ("comment job regains issues: write", lambda t: t.replace("    permissions:\n      pull-requests: write\n", "    permissions:\n      issues: write\n      pull-requests: write\n"), "exactly `pull-requests: write`"),
    ("re-runs share the concurrency group", lambda t: t.replace("-${{ github.run_attempt }}\n", "\n"), "github.run_attempt"),
    ("checkout names the moving merge ref", lambda t: t.replace("        with:\n          # No `ref:`.", "        with:\n          ref: refs/pull/${{ github.event.pull_request.number }}/merge\n          # No `ref:`."), "must not name a ref"),
    ("dependabot not skipped", lambda t: t.replace("      github.actor != 'dependabot[bot]' &&\n", ""), "Dependabot PRs are not skipped"),
    ("secret combined with an untrusted expression", lambda t: t.replace("ENDPOINT: ${{ secrets.CODEX_RESPONSES_ENDPOINT || vars.CODEX_RESPONSES_ENDPOINT }}", "ENDPOINT: ${{ secrets.CODEX_RESPONSES_ENDPOINT || github.head_ref }}"), "secret used outside an env/with mapping value"),
]
for name, mutate, expect in mutations:
    mutated = mutate(text)
    assert mutated != text, f"mutation {name!r} changed nothing; the test is stale"
    found = lint(mutated)
    assert any(expect in p for p in found), f"{name}: expected a problem containing {expect!r}, got {found}"
print(f"  lint fires on all {len(mutations)} mutations")
print("PASS: holdout workflow keeps its security shape, and every lint rule can fail")
EOF
