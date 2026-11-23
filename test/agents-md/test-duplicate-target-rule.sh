#!/usr/bin/env bash
# Two modules writing one target is a registry bug unless the later one lists it
# in `overridesTargets` (agents-md replaces CLAUDE.md that way). --check catches
# it statically; collect_files() refuses it at scaffold time. Both directions of
# a stale declaration are reported too.
set -euo pipefail

python3 - <<'EOF'
import contextlib, io, sys
sys.path.insert(0, '.')
import configure
from configure import MODULES, collect_files, default_form_values


def check_output():
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = configure.run_check()
    return rc, buf.getvalue()


# The shipped registry passes, and the one declared override is real.
rc, out = check_output()
assert rc == 0, out
agents = next(m for m in MODULES if m["id"] == "agents-md")
assert agents["overridesTargets"] == ["CLAUDE.md"], agents.get("overridesTargets")

n = len(MODULES)
try:
    # 1. A module that writes CLAUDE.md WITHOUT declaring the override.
    MODULES.append({"id": "dup", "title": "t", "description": "d",
                    "paths": ["agents-md/CLAUDE.md"]})
    rc, out = check_output()
    assert rc == 1 and "writes CLAUDE.md, which module" in out and "overridesTargets" in out, out

    # ... and the scaffold refuses it too, instead of silently picking a winner.
    try:
        collect_files(default_form_values(), {"core", "dup"}, {})
    except SystemExit as e:
        assert "both write CLAUDE.md" in str(e), e
    else:
        raise AssertionError("collect_files accepted two writers of CLAUDE.md")
    del MODULES[n:]

    # 2. An override of a target this module does not write.
    MODULES.append({"id": "dup", "title": "t", "description": "d",
                    "paths": ["gemini-cli/GEMINI.md"], "overridesTargets": ["nothing.md"]})
    rc, out = check_output()
    assert rc == 1 and "which this module does not write" in out, out
    del MODULES[n:]

    # 3. An override of a target no EARLIER module writes: the module it was meant
    #    to replace is gone. Needs a template that exists only in a temp copy.
    import pathlib, shutil, tempfile
    real = configure.TEMPLATE_DIR
    tmp = pathlib.Path(tempfile.mkdtemp())
    try:
        shutil.copytree(real, tmp / "templates")
        (tmp / "templates" / "zzz").mkdir()
        (tmp / "templates" / "zzz" / "new.md").write_text("x\n", encoding="utf-8")
        configure.TEMPLATE_DIR = tmp / "templates"
        MODULES.append({"id": "dup", "title": "t", "description": "d",
                        "paths": ["zzz/new.md"], "overridesTargets": ["new.md"]})
        rc, out = check_output()
        assert "overridesTargets lists new.md, but no earlier module writes it" in out, out
    finally:
        configure.TEMPLATE_DIR = real
        shutil.rmtree(tmp)
finally:
    del MODULES[n:]

rc, out = check_output()
assert rc == 0, out
print("PASS: duplicate-target rule rejects undeclared, mistargeted and stale overrides; shipped registry passes")
EOF
