#!/usr/bin/env bash
# Verify the --check rule for dynamic-workflow scripts (rule 4b) actually holds.
# Two regression classes, both found by review of the original implementation:
#   1. `meta` was located with text.split("}", 1)[0], which truncates at the
#      first nested brace — a `phases: [{...}]` entry ahead of `name:` made the
#      rule report a missing field that was present.
#   2. the static-import guard was text.lstrip().startswith("import "), which
#      only fires when `import` is the first token in the whole file; a mid-file
#      `import x from "y"` sailed through, and the runtime rejects it.
# Asserts both are caught now, that the shipped workflow stays clean, and that
# a brace inside a description string doesn't unbalance the brace matcher.
set -euo pipefail

python3 - <<'EOF'
import re
import sys
sys.path.insert(0, '.')
from configure import _js_meta_block

def missing(text, field):
    return field not in _js_meta_block(text)

def has_import(text):
    return bool(re.search(r"(?m)^\s*import\s", text)
                or re.search(r"(?<![\w$])import\s*\(", text))

# --- meta block: brace-matched, not split on the first "}" ---

# Case 1: a nested object ahead of name/description must not truncate the block.
phases_first = ("export const meta = {\n"
                "  phases: [{ title: 'A', detail: 'x' }],\n"
                "  name: 'w',\n"
                "  description: 'd',\n"
                "}\n")
assert not missing(phases_first, "name:"), "name: after a nested brace was not found"
assert not missing(phases_first, "description:"), "description: after a nested brace was not found"

# Case 2: a brace inside a string literal must not unbalance the scan.
braced_desc = ("export const meta = {\n"
               "  name: 'w',\n"
               "  description: 'use {slot} syntax',\n"
               "  phases: [{ title: 'A' }],\n"
               "}\n")
assert not missing(braced_desc, "description:"), "brace inside a string broke the matcher"
assert _js_meta_block(braced_desc).endswith("}"), "block did not close on the real terminator"

# Case 3: a genuinely absent field still reports.
no_desc = "export const meta = {\n  name: 'w',\n  phases: [{ title: 'A' }],\n}\n"
assert missing(no_desc, "description:"), "absent description: was not reported"

# Case 4: an unterminated literal yields no block, so the caller can report it.
assert _js_meta_block("export const meta = {\n  name: 'w',\n") == "", \
    "unterminated literal should yield no block"
assert _js_meta_block("const x = 1\n") == "", "no meta block should yield no block"

# --- import guard: any line, not just the first ---

assert has_import("export const meta = { name: 'w', description: 'd' }\n"
                  "const x = 1\n"
                  "import y from 'z'\n"), "mid-file static import was missed"
assert has_import("import y from 'z'\n"
                  "export const meta = { name: 'w', description: 'd' }\n"), \
    "top-of-file static import was missed"
assert has_import("export const meta = { name: 'w', description: 'd' }\n"
                  "await import('x')\n"), "dynamic import() was missed"
assert not has_import("export const meta = { name: 'w', description: 'd' }\n"
                      "// importing is not allowed; see docs\n"
                      "const reimported = 1\n"), "false positive on a comment / identifier"

# --- the shipped workflow must stay clean under all of the above ---
shipped = "templates/multi-agent/dot-claude/workflows/spec-fanout.js"
with open(shipped, encoding="utf-8") as fh:
    text = fh.read()
assert not missing(text, "name:"), f"{shipped}: name: not found"
assert not missing(text, "description:"), f"{shipped}: description: not found"
assert not has_import(text), f"{shipped}: flagged as using import"

print("PASS: workflow meta rule is brace-matched and the import guard covers every line")
EOF
