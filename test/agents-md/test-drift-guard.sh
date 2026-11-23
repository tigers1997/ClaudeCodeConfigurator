#!/usr/bin/env bash
# The --check guard behind agents-md. The two templates are a hand-kept split of
# templates/core/CLAUDE.md, so without it a section edited in one place silently
# diverges from the other. This proves the guard is clean on the shipped
# templates AND fires on each way the split can break: a section that differs,
# a section in neither or both templates, a bridge that does not import, and an
# AGENTS.md that renders over budget.
set -euo pipefail

python3 - <<'EOF'
import pathlib, shutil, sys, tempfile
sys.path.insert(0, '.')
import configure
from configure import find_agents_md_drift, find_agents_md_oversize, _md_sections

# --- the shipped templates are clean ---
assert find_agents_md_drift() == [], find_agents_md_drift()
assert find_agents_md_oversize() == [], find_agents_md_oversize()
print("  shipped templates: no drift, within budget")

# --- _md_sections: level-blind, fence-aware, preamble excluded ---
secs = _md_sections("pre\n\n### A\nbody a\n\n## B\n```\n## not a heading\n```\nbody b\n")
assert list(secs) == ["A", "B"], list(secs)
assert "## not a heading" in secs["B"] and secs["A"] == "body a", secs
assert _md_sections("### X\n1") == _md_sections("## X\n1")
print("  _md_sections: level-blind, fence-aware")

real = configure.TEMPLATE_DIR
real_split = configure.AGENTS_MD_SPLIT_HEADINGS
real_max = configure.AGENTS_MD_MAX_BYTES
tmp = pathlib.Path(tempfile.mkdtemp())


def fresh():
    d = tmp / "templates"
    if d.exists():
        shutil.rmtree(d)
    shutil.copytree(real, d)
    configure.TEMPLATE_DIR = d
    return d


def edit(path, old, new):
    t = path.read_text(encoding="utf-8")
    assert old in t, f"{old!r} not in {path}"
    path.write_text(t.replace(old, new, 1), encoding="utf-8")


def messages():
    return " | ".join(f"{src}: {msg}" for src, msg in find_agents_md_drift())


try:
    # a) a shared section edited in AGENTS.md only
    d = fresh()
    edit(d / "agents-md" / "AGENTS.md", "- Run the test suite before committing.", "- Run tests.")
    m = messages()
    assert "'Testing' differs" in m and "agents-md/AGENTS.md" in m, m

    #    ... accepted once the difference is declared intentional
    configure.AGENTS_MD_SPLIT_HEADINGS = real_split | {"Testing"}
    assert find_agents_md_drift() == [], messages()
    configure.AGENTS_MD_SPLIT_HEADINGS = real_split

    # a') the Claude-only half edited in the bridge only
    d = fresh()
    edit(d / "agents-md" / "CLAUDE.md", "Small diffs.", "Tiny diffs.")
    m = messages()
    assert "'Claude Code behavior rules' differs" in m and "agents-md/CLAUDE.md" in m, m

    # b) the bridge stops importing: the one thing that makes Claude Code read AGENTS.md
    d = fresh()
    edit(d / "agents-md" / "CLAUDE.md", "@AGENTS.md\n", "# no import\n")
    m = messages()
    assert "must be '@AGENTS.md'" in m, m

    # c) a new core section nobody placed
    d = fresh()
    with open(d / "core" / "CLAUDE.md", "a", encoding="utf-8") as fh:
        fh.write("\n## Brand new section\n\nsomething\n")
    m = messages()
    assert "'Brand new section' is in neither template" in m, m

    # d) a section copied into both files
    d = fresh()
    with open(d / "agents-md" / "CLAUDE.md", "a", encoding="utf-8") as fh:
        fh.write("\n## Known gotchas\n\n{{known_gotchas}}\n")
    m = messages()
    assert "'Known gotchas' is in both" in m, m

    # e) over budget: every persona is reported
    fresh()
    configure.AGENTS_MD_MAX_BYTES = 100
    over = find_agents_md_oversize()
    assert {p for p, _ in over} == set(configure.PERSONAS), over
    assert all(size > 100 for _, size in over), over
finally:
    configure.TEMPLATE_DIR = real
    configure.AGENTS_MD_SPLIT_HEADINGS = real_split
    configure.AGENTS_MD_MAX_BYTES = real_max
    shutil.rmtree(tmp)
print("  drift guard fires on: differing section, Claude-half edit, lost import, unplaced section, duplicate section, oversize")
print("PASS: agents-md drift guard is clean on the shipped templates and fires on every break")
EOF
