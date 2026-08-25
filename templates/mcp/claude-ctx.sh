#!/usr/bin/env bash
# claude-ctx <profile> [claude args...]
#
# Launches Claude Code against a task-specific MCP config, ignoring the default
# MCP hierarchy (user/project/local). Profiles live at .mcp.<profile>.json in
# the project root.
#
# WHY this exists: --strict-mcp-config makes the listed servers the ONLY ones
# that exist for the session, so a profile controls which servers actually
# connect: fewer processes and auth prompts at startup, a faster cold start,
# and a smaller blast radius for a task that has no business touching them.
#
# Note on tokens: this used to be pitched as a context saving, and it no longer
# is. Tool search defers MCP tool schemas by default — measured on Claude Code
# 2.1.245, four servers advertising 48 tools between them cost +696 tokens
# deferred versus +14,328 with alwaysLoad: true. Use profiles for connection
# control; use `/context` if you want to see where the tokens really went.
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
