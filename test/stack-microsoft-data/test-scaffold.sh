#!/usr/bin/env bash
# --stack microsoft-data: what lands in the project, and what must not.
#  - the file set, validate.sh executable, nothing left unresolved
#  - the stack's answers replace the web-app defaults that would mislead an agent
#  - AGENTS.md gains the stack's review rules, and WITHOUT the stack renders exactly as before
#  - the Stop hook runs validate.sh through the existing cmd_* slots
#  - permissions: offline validators allowed, every live command ask or deny, never allow
#  - MCP entries: pinned versions, read-only where the server has the flag, no EULA accepted for the user
# `A && B || fail` is the assertion idiom in this file: the fail branch is meant to run when either side is false.
# shellcheck disable=SC2015
set -euo pipefail
# shellcheck source=test/stack-microsoft-data/_common.sh
. test/stack-microsoft-data/_common.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

scaffold "$tmp/a"
a="$tmp/a"
for f in SPEC.md fabric/README.md power-platform/README.md docs/microsoft-data-stack.md AGENTS.md CLAUDE.md \
         .claude/rules/powerbi-tmdl.md .claude/rules/powerbi-report.md .claude/rules/fabric-items.md \
         .claude/rules/power-platform.md scripts/validate.sh scripts/tmdl-check.cs scripts/check_fabric_items.py \
         scripts/report_diagnostics.py .config/dotnet-tools.json ruff.toml .prettierignore \
         .github/workflows/validate.yml; do
    [ -f "$a/$f" ] || { echo "FAIL: --stack microsoft-data did not write $f"; exit 1; }
done
[ -x "$a/scripts/validate.sh" ] || { echo "FAIL: scripts/validate.sh is not executable"; exit 1; }
[ "$(head -n1 "$a/CLAUDE.md")" = "@AGENTS.md" ] || { echo "FAIL: the stack did not pull in the CLAUDE.md bridge"; exit 1; }
for r in powerbi-tmdl powerbi-report fabric-items power-platform; do
    sed -n 2p "$a/.claude/rules/$r.md" | grep -q '^paths: \[' || { echo "FAIL: rule $r has no paths: frontmatter"; exit 1; }
done

# Nothing unresolved. (The workflow's ${{ }} expressions are GitHub's, not ours.)
if grep -rnE '\{\{[a-z_]+\}\}' "$a" --include='*' -l 2>/dev/null | grep -v '\.github/workflows/'; then
    echo "FAIL: unresolved {{placeholder}} in the scaffold"; exit 1
fi
grep -q 'branches: \["main"\]' "$a/.github/workflows/validate.yml" || { echo "FAIL: default branch not substituted in validate.yml"; exit 1; }

# The web-app answers (NextAuth, React state, a test DB on a non-standard port) are replaced, not left behind.
if grep -nE 'NextAuth|React state|Zustand|Layered: routes|test DB uses' "$a/AGENTS.md" "$a/CLAUDE.md"; then
    echo "FAIL: web-app defaults leaked into the Microsoft stack"; exit 1
fi
grep -q 'Contract-first' "$a/AGENTS.md" && grep -q 'Microsoft Entra ID' "$a/AGENTS.md" \
    || { echo "FAIL: the stack's design answers are missing from AGENTS.md"; exit 1; }

# The review rules continue the generic list (6..11) and the file stays well-formed.
python3 - "$a/AGENTS.md" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
sec = t.split("## Code Review Rules", 1)[1].split("\n## ", 1)[0]
nums = [int(n) for n in re.findall(r"^(\d+)\. \*\*", sec, re.M)]
assert nums == list(range(1, 12)), nums
assert "### Fabric, Power BI and Power Platform" in sec
assert "5. **Contracts:**" in sec.split("### Fabric")[0] and "\n\n### Fabric" in sec, "no blank line around the stack heading"
assert "\n\n## Maintaining this file" in t, "no blank line before the next section"
PY

# Without the stack, AGENTS.md carries none of it, and the empty slot leaves no stray blank line.
python3 configure.py --persona solo-experienced --yes --harness agents-md --dir "$tmp/plain" >/dev/null
if grep -qiE 'fabric|power bi|SPEC\.md' "$tmp/plain/AGENTS.md"; then echo "FAIL: stack rules appeared without the stack"; exit 1; fi
grep -q $'authorization, unsafe deserialization, new dependencies.\n5. \*\*Contracts:\*\* public APIs, schemas and docs stay consistent with the code.\n\n## Maintaining this file' "$tmp/plain/AGENTS.md" \
    || { echo "FAIL: AGENTS.md without the stack changed shape (blank line around the empty slot)"; exit 1; }

# The Stop hook runs validate.sh through the cmd_* slots, narrowed by --changed.
grep -qxF '  "typecheck|./scripts/validate.sh --changed models report"' "$a/.claude/hooks/stop-run-checks.sh" \
    && grep -qxF '  "lint|./scripts/validate.sh --changed repo solution"' "$a/.claude/hooks/stop-run-checks.sh" \
    && grep -qxF '  "test|./scripts/validate.sh --changed python"' "$a/.claude/hooks/stop-run-checks.sh" \
    || { echo "FAIL: the Stop hook is not wired to validate.sh"; grep -n '^  "' "$a/.claude/hooks/stop-run-checks.sh"; exit 1; }

# Permissions: nothing that reaches a tenant is ever pre-approved.
python3 - "$a/.claude/settings.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))["permissions"]
allow, ask, deny = p["allow"], p["ask"], p["deny"]
for rule in ("Bash(./scripts/validate.sh:*)", "Bash(python3 scripts/check_fabric_items.py:*)", "Bash(dotnet tool restore)"):
    assert rule in allow, f"{rule} should be allowed"
import re
live = [r for r in allow if re.match(r"Bash\((pac|fab|az|dotnet tool run pac)[ :)]", r)]
assert not live, f"a live-tenant command is pre-approved: {live}"
for rule in ("Bash(pac:*)", "Bash(dotnet tool run pac:*)", "Bash(fab:*)", "Bash(az:*)", "Edit(**/.platform)"):
    assert rule in ask, f"{rule} should ask"
for rule in ("Bash(pac solution delete:*)", "Bash(pac admin delete:*)", "Bash(pac admin reset:*)",
             "Bash(pac auth token:*)", "Bash(fab rm:*)", "Bash(az * delete:*)"):
    assert rule in deny, f"{rule} should be denied"
PY

# .gitignore / .gitattributes
grep -qxF '**/.pbi/localSettings.json' "$a/.gitignore" && grep -qxF '**/.pbi/cache.abf' "$a/.gitignore" \
    || { echo "FAIL: Power BI local state is not ignored"; exit 1; }
grep -qxF 'fabric/** text=auto eol=lf' "$a/.gitattributes" && grep -qxF '*.msapp binary' "$a/.gitattributes" \
    || { echo "FAIL: .gitattributes lacks the Fabric/Power Platform lines"; exit 1; }

# MCP: only Microsoft Learn by default, and it is remote with no auth.
python3 - "$a/.mcp.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))["mcpServers"]
assert s["microsoft-learn"] == {"type": "http", "url": "https://learn.microsoft.com/api/mcp"}, s["microsoft-learn"]
assert not {"azure", "fabric", "powerbi-modeling"} & set(s), sorted(s)
PY

# Every Microsoft MCP server on: pinned, read-only where the flag exists, EULA never accepted for the user.
config_file "$tmp/mcp.json" 'fv.update(mcp_azure=True, mcp_fabric=True, mcp_powerbi_modeling=True)'
python3 configure.py --config "$tmp/mcp.json" --yes --dir "$tmp/m" >/dev/null
python3 - "$tmp/m/.mcp.json" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
s = json.loads(raw)["mcpServers"]
assert "@latest" not in raw, "an unpinned MCP package"
assert s["azure"]["args"] == ["-y", "@azure/mcp@3.0.0", "server", "start", "--read-only"], s["azure"]
assert s["fabric"]["args"] == ["-y", "@microsoft/fabric-mcp@1.8.0", "server", "start", "--read-only"], s["fabric"]
assert s["powerbi-modeling"]["args"] == ["-y", "@microsoft/powerbi-modeling-mcp@1.0.1", "--start"], s["powerbi-modeling"]
assert "accept" not in raw.lower() and "eula" not in raw.lower(), "the scaffold must never accept a EULA on the user's behalf"
PY

# ci_validate off: no workflow. (The doc still describes it, so it must not claim the file exists unconditionally.)
config_file "$tmp/noci.json" 'flags.setdefault("stack-microsoft-data", {})["ci_validate"] = False'
python3 configure.py --config "$tmp/noci.json" --yes --dir "$tmp/n" >/dev/null
[ ! -e "$tmp/n/.github/workflows/validate.yml" ] || { echo "FAIL: ci_validate=false still wrote the workflow"; exit 1; }
[ -f "$tmp/n/scripts/validate.sh" ] || { echo "FAIL: ci_validate=false dropped the validator"; exit 1; }

# The validator accepts every tier the preset's commands name.
git_init "$a"
for tier in repo models report solution python; do
    (cd "$a" && ./scripts/validate.sh --changed "$tier" >/dev/null 2>&1) || { echo "FAIL: validate.sh rejected the tier '$tier' that the preset names"; exit 1; }
done

echo "PASS: the Microsoft stack scaffold is complete, replaces web-app defaults, splices the review rules, and never pre-approves a live command"
