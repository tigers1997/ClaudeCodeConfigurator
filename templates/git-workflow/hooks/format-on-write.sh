#!/usr/bin/env bash
# PostToolUse hook — autoformats files after Claude writes or edits them.
# Wire under hooks.PostToolUse with matcher: "Write|Edit".
set -euo pipefail

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;d=json.load(sys.stdin).get("tool_input",{});print(d.get("file_path") or d.get("path") or "")')"

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Skip dotfiles in sensitive dirs.
case "$FILE" in
  */.git/*|*/node_modules/*|*/.venv/*|*/dist/*|*/build/*) exit 0 ;;
esac

case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.md|*.css|*.html|*.yml|*.yaml)
    command -v prettier >/dev/null && prettier --write --log-level=warn "$FILE" || true
    ;;
  *.py)
    command -v ruff >/dev/null && ruff format "$FILE" >/dev/null 2>&1 || true
    command -v ruff >/dev/null && ruff check --fix --quiet "$FILE" >/dev/null 2>&1 || true
    ;;
  *.go)
    command -v gofmt >/dev/null && gofmt -w "$FILE" || true
    ;;
  *.rs)
    command -v rustfmt >/dev/null && rustfmt --edition 2021 "$FILE" 2>/dev/null || true
    ;;
esac

exit 0
