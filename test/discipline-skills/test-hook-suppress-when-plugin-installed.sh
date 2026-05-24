#!/usr/bin/env bash
# When the upstream superpowers plugin is also installed, the configurator's
# bootstrap hook must exit silently (no output) — superpowers' own hook
# handles priming.
set -euo pipefail

tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# Simulate plugin presence
mkdir -p "$tmp/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0"

out=$(HOME="$tmp" CLAUDE_PROJECT_DIR="$tmp" bash templates/discipline-skills/hooks/sessionstart-discipline.sh 2>&1)

[ -z "$out" ] || { echo "FAIL: hook produced output when plugin installed: $out"; exit 1; }

echo "PASS: hook silent when superpowers plugin is installed"
