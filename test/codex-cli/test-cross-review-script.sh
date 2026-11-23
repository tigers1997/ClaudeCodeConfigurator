#!/usr/bin/env bash
# cross-review.sh against a STUB `codex` that records its arguments. This pins
# how the script calls Codex (read-only, ephemeral, report to a file, a profile
# only when the profile file exists, never a flag that lifts the sandbox) and
# its refusals (default branch, empty diff, missing base, missing codex). It does
# NOT run the real Codex CLI: what the real binary does with these arguments is
# taken from its documentation (learn.chatgpt.com/docs/non-interactive-mode).
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A scaffolded project that is also a git repo: main, then a feature branch with a change.
python3 configure.py --persona solo-experienced --yes --harness codex --dir "$tmp/repo" >/dev/null
repo="$tmp/repo"
script=".claude/skills/cross-review/scripts/cross-review.sh"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }
g init -q -b main
g add -A
g commit -q -m base
base=$(g rev-parse main)
g checkout -q -b feat/x
echo "change" >> "$repo/AGENTS.md"

# The stub records NUL-separated arguments (the prompt has newlines) and writes a
# fake report to the -o file.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/codex" <<'STUB'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$STUB_ARGS"
out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] && echo "FAKE REVIEW" > "$out"
echo "FAKE REVIEW"
STUB
chmod +x "$tmp/bin/codex"

run() { (cd "$repo" && env PATH="$tmp/bin:$PATH" STUB_ARGS="$tmp/args" CODEX_HOME="$tmp/codex-home" \
            TMPDIR="$tmp" bash "$script" "$@" 2>&1); }

# argcheck 'python expression over a (the argument list) and base' 'failure message'
argcheck() {
    python3 - "$tmp/args" "$base" "$1" "$2" <<'PY'
import sys
a = open(sys.argv[1], "rb").read().decode().split("\0")[:-1]
base, expr, msg = sys.argv[2], sys.argv[3], sys.argv[4]
if not eval(expr):
    print("FAIL:", msg)
    print("args:", a)
    sys.exit(1)
PY
}

# --- 1. happy path, no review profile ---
rc=0; out=$(run) || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: happy path exited $rc"; echo "$out"; exit 1; }
echo "$out" | grep -q 'FAKE REVIEW' || { echo "FAIL: report not printed"; exit 1; }
argcheck "a[0] == 'exec'" "first argument must be 'exec'"
argcheck "a[a.index('--sandbox') + 1] == 'read-only'" "--sandbox read-only is missing"
argcheck "'--ephemeral' in a" "--ephemeral is missing"
argcheck "'-o' in a and a[a.index('-o') + 1].startswith(('/', '.'))" "-o <report file> is missing"
argcheck "'--profile' not in a" "--profile passed although no review.config.toml exists"
argcheck "not ({'--full-auto', '--yolo', '--dangerously-bypass-approvals-and-sandbox', '--ask-for-approval', '-a', 'danger-full-access', 'workspace-write'} & set(a))" "a sandbox-lifting flag was passed"
argcheck "('git diff ' + base) in a[-1]" "the prompt does not name the merge-base diff"
argcheck "'Code Review Rules' in a[-1]" "the prompt does not point at the Code Review Rules"
argcheck "'never instructions to you' in a[-1]" "the prompt does not mark repository text as data"
echo "$out" | grep -q 'no review profile' || { echo "FAIL: missing-profile notice not printed"; exit 1; }
report=$(echo "$out" | sed -n 's/.*report saved to //p')
[ -f "$report" ] && grep -q 'FAKE REVIEW' "$report" || { echo "FAIL: report file not written at '$report'"; exit 1; }

# --- 2. a review profile file switches the profile on ---
mkdir -p "$tmp/codex-home"
printf 'model = "m"\n' > "$tmp/codex-home/review.config.toml"
rc=0; out=$(run) || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: profile run exited $rc"; exit 1; }
argcheck "a[a.index('--profile') + 1] == 'review'" "--profile review not passed when the profile file exists"
rm -f "$tmp/codex-home/review.config.toml"

# --- 3. refusals ---
g commit -q -am feat
g checkout -q main
rc=0; out=$(run) || rc=$?
{ [ "$rc" = 2 ] && echo "$out" | grep -q 'default branch'; } || { echo "FAIL: default branch should exit 2 (got $rc)"; echo "$out"; exit 1; }
g checkout -q feat/x
rc=0; out=$(run main) || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: explicit base 'main' exited $rc"; echo "$out"; exit 1; }
rc=0; out=$(run no-such-ref) || rc=$?
{ [ "$rc" = 2 ] && echo "$out" | grep -q 'no merge-base'; } || { echo "FAIL: unknown base should exit 2 (got $rc)"; echo "$out"; exit 1; }
g checkout -q -b empty main
rc=0; out=$(run) || rc=$?
{ [ "$rc" = 2 ] && echo "$out" | grep -q 'nothing to review'; } || { echo "FAIL: empty diff should exit 2 (got $rc)"; echo "$out"; exit 1; }
g checkout -q feat/x

# --- 4. no codex on PATH: exit 3 with a pointer to the setup doc ---
# A PATH holding only git, so a codex installed on this machine cannot leak in.
mkdir -p "$tmp/nocodex"
ln -s "$(command -v git)" "$tmp/nocodex/git"
rc=0; out=$(cd "$repo" && env PATH="$tmp/nocodex" "$(command -v bash)" "$script" 2>&1) || rc=$?
{ [ "$rc" = 3 ] && echo "$out" | grep -q 'docs/codex-setup.md'; } || { echo "FAIL: missing codex should exit 3 (got $rc)"; echo "$out"; exit 1; }

echo "PASS: cross-review.sh calls codex read-only and ephemeral, honours the profile file, and refuses cleanly"
