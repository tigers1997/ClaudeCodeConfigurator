# example-profile-budget — context cost of running with `.mcp.research.json` vs default

## Hypothesis
Scoping the session to a single task-specific MCP config (`.mcp.research.json`, which only enables context7) will drop the baseline MCP cost from ~37k tokens to under 5k, freeing >30k for the actual work.

## Setup
- Command: `./claude-ctx research` (shipped by the `mcp` module). Expands to `claude --mcp-config .mcp.research.json --strict-mcp-config`.
- Control: plain `claude` with the full default MCP hierarchy (filesystem + git + github + context7 all enabled).
- Measurement: run `/context` on a fresh session with no user prompt. Record the MCP tool-descriptions row.

## Result
Control (default hierarchy, 4 servers): 37,600 tokens of MCP tool descriptions (per Marco p.109, matches observation).
Scoped (`research` profile, context7 only): 4,200 tokens.
Delta: ~33.4k tokens reclaimed. Session context at first turn went from 49% → 14% occupied.

## Conclusion
Hypothesis held. The `--strict-mcp-config` flag is the key — without it the scoped file merges with the default hierarchy and the savings disappear. Codified as: default working mode for research/debugging sessions is now `./claude-ctx research`, not plain `claude`. `claude` without a profile is reserved for sessions that genuinely need filesystem+git+github simultaneously.

## Addendum (2026-08-25) — superseded by tool search

Claude Code now defers MCP tool schemas by default (`alwaysLoad: true` opts a
server out), so the control condition this experiment measured no longer
happens on a current build. Re-measured with four servers advertising 48 tools
on CC 2.1.245: +696 tokens deferred versus +14,328 eagerly loaded, against a
~26.7k baseline with no servers at all. The conclusion below still holds for
`alwaysLoad` servers and for builds predating tool search; the headline saving
does not generalize. Left in place deliberately — an experiment log records what
was true when it ran, and the addendum is where the update belongs.

## Follow-ups
- Measure the `minimal` profile the same way — expected ~0 tokens for MCP, but is there overhead from the empty `mcpServers: {}` itself?
- Try the `frontend` profile on a real UI bug to see if playwright alone is enough or if filesystem access is needed too.
- Consider a `writer` profile distinct from `minimal` — pure writing might still want context7 for accurate API citations.
