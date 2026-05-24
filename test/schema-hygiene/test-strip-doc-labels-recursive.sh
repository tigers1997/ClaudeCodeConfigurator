#!/usr/bin/env bash
# Verify _strip_doc_labels() recursively removes all //-prefixed keys at
# any nesting depth, not just top-level. This is the regression guard for
# nested cases like statusLine.// hideVimModeIndicator that the shallow
# per-merge filters miss.
set -euo pipefail

python3 - <<'EOF'
import sys
sys.path.insert(0, '.')
from configure import _strip_doc_labels

# Top-level doc labels
out = _strip_doc_labels({"//": "doc", "//2": "more doc", "active": "keep"})
assert out == {"active": "keep"}, f"top-level: {out}"

# Top-level stub
out = _strip_doc_labels({"// sandbox": {"x": 1}, "real": "keep"})
assert out == {"real": "keep"}, f"top-level stub: {out}"

# Nested doc label
out = _strip_doc_labels({"statusLine": {"//": "doc", "type": "command"}})
assert out == {"statusLine": {"type": "command"}}, f"nested label: {out}"

# Nested stub
out = _strip_doc_labels({"statusLine": {"// hideVimModeIndicator": True, "type": "command"}})
assert out == {"statusLine": {"type": "command"}}, f"nested stub: {out}"

# Stub inside list element (defensive — JSON lists can contain dicts)
out = _strip_doc_labels({"hooks": [{"// label": "doc", "matcher": "Bash"}]})
assert out == {"hooks": [{"matcher": "Bash"}]}, f"list: {out}"

# Empty + non-dict pass-through
assert _strip_doc_labels({}) == {}
assert _strip_doc_labels([]) == []
assert _strip_doc_labels("string") == "string"
assert _strip_doc_labels(42) == 42
assert _strip_doc_labels(True) == True
assert _strip_doc_labels(None) == None

print("PASS: _strip_doc_labels recursively removes //-prefixed keys at all depths")
EOF
