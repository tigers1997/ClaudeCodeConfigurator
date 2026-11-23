#!/usr/bin/env bash
# The generated validate.yml: read-only, no secrets, SHA-pinned, and --strict.
# --strict is the point: without it a runner that lacks .NET, Node or pac would
# SKIP the tiers and the check would go green having validated nothing. Each rule
# is proved by a mutation that must make the lint complain. actionlint is run too
# when it is installed.
set -euo pipefail
. test/stack-microsoft-data/_common.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
scaffold "$tmp/p"

python3 - "$tmp/p/.github/workflows/validate.yml" <<'EOF'
import re, sys

text = open(sys.argv[1], encoding="utf-8").read()


def lint(t):
    t = "\n".join(l for l in t.splitlines() if not l.lstrip().startswith("#")) + "\n"
    out = []
    ok = lambda cond, msg: out.append(msg) if not cond else None
    ok(re.search(r"^on:\n  pull_request:\n  push:\n    branches: \[\"[^\"]+\"\]\n", t, re.M), "triggers must be pull_request and a push to the default branch")
    for bad in ("pull_request_target", "workflow_run", "issue_comment", "workflow_dispatch"):
        ok(bad not in t, f"uses the {bad} trigger")
    ok(re.search(r"^permissions:\n  contents: read\n(?!  )", t, re.M), "top-level permissions must be exactly contents: read")
    ok("write" not in t, "a write permission appears")
    ok("secrets." not in t, "a secret is referenced; validation needs none")
    ok("timeout-minutes:" in t, "no timeout")
    ok(re.search(r"^concurrency:\n  group: .+\n  cancel-in-progress: true", t, re.M), "no concurrency group")
    uses = re.findall(r"uses:\s*(\S+)", t)
    ok(len(uses) == 4, f"expected checkout, setup-dotnet, setup-node, setup-uv; got {uses}")
    for u in uses:
        ok(re.search(r"@[0-9a-f]{40}$", u), f"{u} is not pinned to a commit SHA")
    ok("persist-credentials: false" in t, "checkout must not persist credentials")
    ok("dotnet-version: 10.0.x" in t, "the TMDL parse needs the .NET 10 SDK")
    ok(re.search(r"node-version: (2\d|[3-9]\d)\b", t), "the PBIR validator needs Node 20+")
    ok("dotnet tool restore" in t, "pac is not restored from the manifest")
    ok(re.search(r"run: \./scripts/validate\.sh --strict\s*$", t, re.M), "validate.sh must run with --strict")
    ok("hashFiles('pyproject.toml')" in t, "uv should only be set up when the repo has Python")
    for m in re.finditer(r"^( *)run: \|\n", t, re.M):
        body = []
        for ln in t[m.end():].splitlines():
            if ln.strip() and len(ln) - len(ln.lstrip()) <= len(m.group(1)):
                break
            body.append(ln)
        ok("${{" not in "\n".join(body), "an expression is expanded inside a run body")
    # No YAML library here (stdlib only), so lint the one class of syntax error that bit this
    # file: an unquoted "key: value" whose value itself contains ": " parses as a nested
    # mapping and the whole workflow is rejected. actionlint found it; CI does not run actionlint.
    block_indent = None
    for n, ln in enumerate(t.splitlines(), 1):
        indent = len(ln) - len(ln.lstrip())
        if block_indent is not None:
            if ln.strip() and indent <= block_indent:
                block_indent = None
            else:
                continue
        if re.search(r":\s+[|>][+-]?\s*$", ln):
            block_indent = indent
            continue
        m = re.match(r"^\s*(?:- )?[A-Za-z0-9_.-]+:\s+([^\s'\"|>\[{&*!%@`#].*)$", ln)
        if m:
            value = re.split(r"\s#", m.group(1), maxsplit=1)[0]
            ok(": " not in value and not value.endswith(":"),
               f"line {n}: a plain scalar contains ': ' (invalid YAML, quote it): {ln.strip()}")
    return out


assert lint(text) == [], lint(text)
checks = [
    ("pull_request_target", lambda t: t.replace("on:\n  pull_request:\n", "on:\n  pull_request_target:\n"), "trigger"),
    ("write permission", lambda t: t.replace("  contents: read\n", "  contents: write\n", 1), "contents: read"),
    ("a secret", lambda t: t.replace("run: dotnet tool restore", "run: echo ${{ secrets.X }}"), "secret"),
    ("unpinned action", lambda t: re.sub(r"(actions/setup-node)@[0-9a-f]{40}", r"\1@v7", t), "not pinned"),
    ("no --strict", lambda t: t.replace("validate.sh --strict", "validate.sh"), "--strict"),
    ("credentials persisted", lambda t: t.replace("persist-credentials: false", "persist-credentials: true"), "persist credentials"),
    ("wrong .NET", lambda t: t.replace("10.0.x", "8.0.x"), ".NET 10"),
    ("old Node", lambda t: t.replace("node-version: 22", "node-version: 18"), "Node 20"),
    ("no restore", lambda t: t.replace("run: dotnet tool restore", "run: echo skip"), "restored"),
    ("expression in run", lambda t: t.replace("run: dotnet tool restore", "run: |\n          echo ${{ github.ref }}"), "run body"),
    ("no timeout", lambda t: t.replace("    timeout-minutes: 20\n", ""), "timeout"),
    ("YAML plain scalar containing ': '", lambda t: t.replace("name: Validate (strict, so a skipped tier fails)", "name: Validate (strict: a skipped tier fails)"), "plain scalar"),
]
for name, mutate, expect in checks:
    mutated = mutate(text)
    assert mutated != text, f"mutation {name!r} changed nothing"
    problems = lint(mutated)
    assert any(expect in p for p in problems), f"{name}: expected a problem containing {expect!r}, got {problems}"
print(f"  lint clean on the shipped workflow, fires on all {len(checks)} mutations")
EOF

if command -v actionlint >/dev/null 2>&1; then
    actionlint "$tmp/p/.github/workflows/validate.yml" || { echo "FAIL: actionlint found problems"; exit 1; }
    echo "  actionlint: clean"
else
    echo "  (actionlint not installed; the structural lint above still ran)"
fi
echo "PASS: validate.yml is read-only, secret-free, SHA-pinned and strict"
