#!/usr/bin/env bash
# The breakage watch that replaced the per-release Claude Code survey at the
# 2.1.310 freeze: (1) every hook event a shipped patch wires is one Claude Code
# knows, (2) no shipped skill takes a built-in command or bundled skill name,
# (3) the version preflight says the right thing below the minimum, above the
# designed-for version, and for the PowerShell variants' own floor.
set -euo pipefail

python3 - <<'EOF'
import json, pathlib, shutil, subprocess, sys, tempfile, types
sys.path.insert(0, '.')
import configure
from configure import find_unknown_hook_events, find_reserved_skill_names, check_claude_code_version
from config_schema import (KNOWN_HOOK_EVENTS, RESERVED_SKILL_NAMES,
                           RESERVED_SKILL_NAME_EXCEPTIONS, CLAUDE_CODE_COMPAT)

# (1) + (2): the shipped templates are clean, and the lists are sane.
assert find_unknown_hook_events() == [], find_unknown_hook_events()
assert find_reserved_skill_names() == [], find_reserved_skill_names()
for ev in ("PreToolUse", "PostToolUse", "Stop", "SessionStart", "PreCompact"):
    assert ev in KNOWN_HOOK_EVENTS, ev
for name in ("review", "verify", "code-review", "plan", "run", "batch"):
    assert name in RESERVED_SKILL_NAMES, name
assert "plan" in RESERVED_SKILL_NAME_EXCEPTIONS
for name in ("review-branch", "commit", "ship", "verify-setup", "freeze"):
    assert name not in RESERVED_SKILL_NAMES, name

# The rules actually fire: plant a bad patch and a reserved-name skill in a
# temporary copy of templates/ and point the finders at it.
tmp = pathlib.Path(tempfile.mkdtemp())
shutil.copytree(configure.TEMPLATE_DIR, tmp / "templates")
(tmp / "templates" / "safety" / "settings-patch.bogus.json").write_text(
    json.dumps({"hooks": {"PreToolUse": [], "ToolRan": []}}), encoding="utf-8")
(tmp / "templates" / "commands" / "review").mkdir()
(tmp / "templates" / "commands" / "review" / "SKILL.md").write_text(
    "---\nname: review\ndescription: x\n---\n", encoding="utf-8")
real_dir = configure.TEMPLATE_DIR
configure.TEMPLATE_DIR = tmp / "templates"
try:
    bad_events = find_unknown_hook_events()
    assert any(ev == "ToolRan" for _, ev in bad_events), bad_events
    assert not any(ev == "PreToolUse" for _, ev in bad_events), bad_events
    bad_names = find_reserved_skill_names()
    assert any(n == "review" for _, n in bad_names), bad_names
    assert not any(n == "plan" for _, n in bad_names), "plan is the documented exception"
finally:
    configure.TEMPLATE_DIR = real_dir
    shutil.rmtree(tmp)
print("  breakage watch: clean on shipped templates, fires on a planted event and name")

# (3) version preflight wording, with a fake `claude --version`.
def fake(version):
    def run(*a, **k):
        return types.SimpleNamespace(returncode=0, stdout=f"{version} (Claude Code)")
    return run
real_run = subprocess.run
try:
    subprocess.run = fake("2.1.300")
    w = check_claude_code_version()
    assert len(w) == 1 and "below the supported minimum" in w[0] and "2.1.304" in w[0], w
    assert "vanish" in w[0] and "2.1.299" in w[0], w
    subprocess.run = fake(CLAUDE_CODE_COMPAT["tested_up_to"])
    assert check_claude_code_version() == [], check_claude_code_version()
    assert check_claude_code_version("powershell") == []
    subprocess.run = fake("2.1.350")
    w = check_claude_code_version()
    assert len(w) == 1 and "designed for" in w[0] and "expected to work" in w[0], w
    subprocess.run = fake("2.1.306")
    w = check_claude_code_version("powershell")
    assert any("--hook-shell powershell needs Claude Code 2.1.309" in m for m in w), w
    assert not any("below the supported minimum" in m for m in w), w
    assert check_claude_code_version("bash") == []
finally:
    subprocess.run = real_run
print("  version preflight: below-min, in-range, above-designed-for, PowerShell floor all worded correctly")
print("PASS: breakage watch rules and version preflight behave")
EOF
