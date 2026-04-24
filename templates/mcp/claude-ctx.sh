#!/usr/bin/env bash
# claude-ctx <profile> [claude args...]
#
# Launches Claude Code against a task-specific MCP config, ignoring the default
# MCP hierarchy (user/project/local). Profiles live at .mcp.<profile>.json in
# the project root.
#
# WHY this exists: a fresh session with 4 MCP servers loaded burns ~49% of a
# 100k context window before you type anything (system prompt ~2.2k +
# system tool descriptions ~12k + MCP tool descriptions ~37k). Scoping per
# task with --strict-mcp-config drops that cost to near-zero for tasks that
# don't need those servers.
#
# Usage:
#   ./claude-ctx research                    # loads only .mcp.research.json
#   ./claude-ctx frontend --resume           # profile + extra claude args
#   ./claude-ctx minimal                     # empty mcpServers -> no MCP load
#
# See docs/mcp-servers.md for the full pattern and when to use each profile.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: claude-ctx <profile> [claude args...]" >&2
  echo "available profiles in $(pwd):" >&2
  shopt -s nullglob
  found=0
  for f in .mcp.*.json; do
    base="${f#.mcp.}"
    name="${base%.json}"
    printf "  %s\n" "$name" >&2
    found=1
  done
  if [ "$found" -eq 0 ]; then
    echo "  (none — create .mcp.<name>.json first)" >&2
  fi
  exit 2
fi

PROFILE="$1"; shift
CONFIG=".mcp.${PROFILE}.json"

if [ ! -f "$CONFIG" ]; then
  echo "claude-ctx: no config at $CONFIG" >&2
  echo "create one (see .mcp.research.json for an example) or see docs/mcp-servers.md" >&2
  exit 1
fi

exec claude --mcp-config "$CONFIG" --strict-mcp-config "$@"
