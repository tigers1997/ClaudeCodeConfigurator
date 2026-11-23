#!/usr/bin/env bash
# The review job's second step stops when the checked-out merge commit does not contain
# the event's PR head. GitHub can hand a job a merge commit made before the latest push
# (the checkout action only records that and carries on), and a review of it would read
# files and a diff from different revisions yet be posted as the review of the new head.
# The step's shell is extracted from the generated workflow and EXECUTED here, in a real
# git repository, for: the merge commit GitHub would hand over; a merge commit that
# predates a later push; and a checkout that is not a merge commit at all.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 test/codex-cli/_make-config.py "$tmp/c.json" holdout_ci=1
python3 configure.py --config "$tmp/c.json" --yes --dir "$tmp/p" >/dev/null

python3 - "$tmp/p/.github/workflows/holdout-review.yml" "$tmp/check.sh" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"- name: Check the checkout is this event's merge commit\n(?:.*\n)*?( *)run: \|\n", text)
assert m, "no `Check the checkout is this event's merge commit` step with a `run: |` body"
base = len(m.group(1))
body = []
for ln in text[m.end():].splitlines():
    if ln.strip() and len(ln) - len(ln.lstrip()) <= base:
        break
    body.append(ln[base + 2:] if ln.strip() else "")
open(sys.argv[2], "w", encoding="utf-8").write("#!/usr/bin/env bash\n" + "\n".join(body) + "\n")
PY

g() { git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false -c tag.gpgsign=false -c init.defaultBranch=main "$@"; }
repo="$tmp/r"
mkdir "$repo"
(
    cd "$repo"
    g init -q .
    echo base > f; g add f; g commit -qm base
    g switch -q -c pr
    echo one > one; g add one; g commit -qm head1
    git rev-parse HEAD > "$tmp/head1"
    g switch -q main
    g merge -q --no-ff pr -m "Merge $(cat "$tmp/head1") into base"      # the merge commit GitHub hands the job
    git rev-parse HEAD > "$tmp/merge1"
    g switch -q pr
    echo two > two; g add two; g commit -qm head2                         # a push the merge commit predates
    git rev-parse HEAD > "$tmp/head2"
)

# run <name> <commit checked out> <HEAD_SHA> <expected exit> <expected text or ->
run() {
    local name=$1 at=$2 head=$3 want=$4 text=$5 out rc=0
    out=$(cd "$repo" && g checkout -q --detach "$at" && env -i PATH="$PATH" HEAD_SHA="$head" bash "$tmp/check.sh" 2>&1) || rc=$?
    [ "$rc" = "$want" ] || { echo "FAIL: $name: exit $rc, wanted $want"; echo "$out"; exit 1; }
    if [ "$text" != "-" ]; then
        echo "$out" | grep -q -F -- "$text" || { echo "FAIL: $name: output lacks '$text'"; echo "$out"; exit 1; }
    fi
}

run "merge commit contains the event's head"      "$(cat "$tmp/merge1")" "$(cat "$tmp/head1")" 0 -
run "stale merge: a later push is not in it"     "$(cat "$tmp/merge1")" "$(cat "$tmp/head2")" 1 "predates the latest push"
run "not a merge commit at all"                   "$(cat "$tmp/head1")"  "$(cat "$tmp/head1")" 1 "predates the latest push"
run "an empty HEAD_SHA never matches"             "$(cat "$tmp/merge1")" ""                    1 "predates the latest push"

echo "PASS: the merge-commit check accepts the event's merge commit and stops on a stale merge, a plain commit and an empty head"
