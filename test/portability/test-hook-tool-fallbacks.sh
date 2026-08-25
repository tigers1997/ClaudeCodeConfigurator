#!/usr/bin/env bash
# Shipped hooks must not depend on tools that aren't there.
#
#   stop-run-checks.sh   emitted its report with an unguarded `jq -n`. jq is not
#                        preinstalled on macOS, Windows, or most Linux distros,
#                        so on those machines the checks ran, the hook exited 0,
#                        and Claude never learned anything had failed — the
#                        entire point of the hook, lost silently.
#   check-package-availability.sh  bounded each probe with GNU `timeout`, absent
#                        on stock macOS. The resulting rc=127 took the
#                        "inconclusive" branch, so the gate disabled itself on
#                        the first package for every macOS user.
#
# Both are tested by running the real scaffolded hook under a PATH that hides
# the tool, not by grepping the source.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null

REAL_BASH="$(command -v bash)"
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"

# Passthrough shims for the utilities the hooks genuinely need, so PATH can be
# narrowed to exactly this directory. Written as scripts with an absolute
# shebang rather than symlinks, because `ln -s` copies on Git Bash.
shim() {
    local name=$1 real
    real="$(command -v "$name" 2>/dev/null)" || return 0
    printf '#!%s\nexec "%s" "$@"\n' "$REAL_BASH" "$real" > "$fakebin/$name"
    chmod +x "$fakebin/$name"
}
for b in tr wc grep awk tail sed cat head cut sort uniq bash; do shim "$b"; done

# ---------------------------------------------------------------- stop-run-checks
hook="$tmp/.claude/hooks/stop-run-checks.sh"
echo '{}' > "$tmp/package.json"          # satisfy the manifest guard
cat > "$fakebin/pnpm" <<EOF
#!$REAL_BASH
echo "simulated check failure" >&2
exit 7
EOF
chmod +x "$fakebin/pnpm"

# --- case 1: no jq, python3 present -> report still emitted as valid JSON ---
shim python3
out="$(CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin" bash "$hook" 2>/dev/null || true)"
[ -n "$out" ] || { echo "FAIL: no stdout from the Stop hook when jq is absent"; exit 1; }
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
hso = d["hookSpecificOutput"]
assert hso["hookEventName"] == "Stop", hso
assert "FAIL" in hso["additionalContext"], hso["additionalContext"][:200]
' || { echo "FAIL: jq-less fallback did not emit a valid Stop report"; echo "  got: ${out:0:200}"; exit 1; }

# --- case 2: neither jq nor python3 -> loud on stderr, never silent ---
rm -f "$fakebin/python3"
err="$tmp/err.txt"
out="$(CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin" bash "$hook" 2>"$err" || true)"
grep -q "NOT reaching Claude" "$err" \
    || { echo "FAIL: with no JSON tool the hook stayed silent instead of warning"; echo "  stderr: $(head -c 200 "$err")"; exit 1; }
grep -q "simulated check failure" "$err" \
    || { echo "FAIL: the report body wasn't surfaced on stderr as a last resort"; exit 1; }

# ---------------------------------------------------------------- availability gate
# The gate must still reach a verdict with no `timeout` binary on PATH. Without
# the fallback it printed "probe inconclusive" and exited before gating at all.
avail="$tmp/.claude/hooks/check-package-availability.sh"
[ -f "$avail" ] || { echo "FAIL: availability hook not scaffolded"; exit 1; }
for b in jq apt-cache dpkg-query; do shim "$b"; done   # jq IS needed by this hook
payload='{"tool_name":"Bash","tool_input":{"command":"apt install definitely-not-a-real-package-xyz"}}'
err2="$tmp/err2.txt"
printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$tmp" PATH="$fakebin" bash "$avail" >/dev/null 2>"$err2" || true
if grep -q "probe inconclusive" "$err2"; then
    echo "FAIL: availability gate went inconclusive with no timeout binary (the macOS bug)"
    echo "  stderr: $(head -c 200 "$err2")"
    exit 1
fi

echo "PASS: Stop hook reports without jq and warns without any JSON tool; availability gate survives a missing timeout"
