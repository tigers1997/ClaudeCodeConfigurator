#!/usr/bin/env bash
# v1 NOTICE branch already prompts for persona. quick_interactive must NOT
# re-prompt — that's a UX bug where the user sees the persona menu twice.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

cat > "$tmp/.claude-config.json" <<JSON
{
  "formValues": {"project_name": "test", "stack_preset": "Python (uv)"},
  "selected": ["core", "safety"],
  "_version": 1
}
JSON

# Pipe Enter for every prompt; with the bug there are 2 persona prompts.
out=$(printf '\n\n\n\n\n\n' | python3 configure.py --dry-run --dir "$tmp" 2>&1 || true)
count=$(echo "$out" | grep -c "Persona — pick a sensible kit" || true)
[ "$count" = "1" ] || { echo "FAIL: expected 1 persona prompt, got $count"; echo "---OUTPUT---"; echo "$out"; exit 1; }
echo "PASS: v1 NOTICE branch + quick_interactive prompt for persona only once"
