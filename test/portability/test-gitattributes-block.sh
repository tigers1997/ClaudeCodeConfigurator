#!/usr/bin/env bash
# The scaffold appends a .gitattributes block pinning eol=lf for the bash
# scripts, so a Windows checkout (core.autocrlf=true) or a CRLF-saving editor
# can't reintroduce a CR into a shebang and break the hooks for teammates on
# Linux/macOS. Same managed-block semantics as the .gitignore block: write it
# when absent, union in missing rules when a prior scaffold's block is there,
# never touch the user's own lines.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# --- case 1: fresh project gets the block ---
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
ga="$tmp/.gitattributes"
[ -f "$ga" ] || { echo "FAIL: no .gitattributes written"; exit 1; }
grep -q '^\*\.sh text eol=lf$' "$ga" || { echo "FAIL: *.sh eol=lf rule missing"; exit 1; }
grep -q '^claude-ctx text eol=lf$' "$ga" || { echo "FAIL: claude-ctx eol=lf rule missing"; exit 1; }

# --- case 2: re-running must not duplicate the block ---
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
markers=$(grep -c -- '--- Claude Code ---' "$ga")
[ "$markers" = "1" ] || { echo "FAIL: block appears $markers times after retrofit (want 1)"; exit 1; }

# --- case 3: user content preserved, missing rules unioned in ---
rm -f "$ga"
cat > "$ga" <<'EOF'
# my project's own rules
*.png binary

# --- Claude Code ---
*.sh text eol=lf
EOF
python3 configure.py --persona solo-experienced --yes --dir "$tmp" >/dev/null
grep -q '^\*\.png binary$' "$ga" || { echo "FAIL: user's own rule was lost"; exit 1; }
grep -q '^claude-ctx text eol=lf$' "$ga" \
    || { echo "FAIL: rule missing from a stale block wasn't unioned in"; exit 1; }
markers=$(grep -c -- '--- Claude Code ---' "$ga")
[ "$markers" = "1" ] || { echo "FAIL: stale-block union duplicated the marker ($markers)"; exit 1; }
dupes=$(grep -c '^\*\.sh text eol=lf$' "$ga")
[ "$dupes" = "1" ] || { echo "FAIL: already-present rule re-appended ($dupes copies)"; exit 1; }

# --- case 4: the rules actually match what the scaffold writes ---
[ -f "$tmp/claude-ctx" ] || { echo "FAIL: claude-ctx not scaffolded — rule would be dead"; exit 1; }

echo "PASS: .gitattributes block written, idempotent, unions stale blocks, preserves user rules"
