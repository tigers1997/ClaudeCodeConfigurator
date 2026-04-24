---
name: check-context
description: Break down what's in the current context window and flag bloat. Use before long sessions or when autocompaction fires earlier than expected.
{{effort_frontmatter}}allowed-tools: Bash(claude:*)
---

# Check the context budget

Run `/context` first (the built-in) and read the breakdown it prints. Then analyze the slices below and report whether any are out of bounds.

## Budget guardrails

A fresh Claude Code session with 4 MCP servers loaded already burns ~49% of a 100k window before the user types anything — system prompt ~2.2k, system tool descriptions ~12k, MCP tool descriptions ~37k. That's the baseline to compare against.

Flag the following:

- **MCP tool descriptions > 10%** of the window → too many MCP servers for this task. Recommend the user split per-task `.mcp.json.<profile>` files and run `claude --mcp-config <path> --strict-mcp-config`.
- **Custom tools / skills > 5%** of the window → some skill descriptions are too verbose or too many user-invocable skills are loaded. Recommend auditing `allowed-tools`, `when_to_use`, and trimming descriptions.
- **Memory (CLAUDE.md + @imports) > 10%** → CLAUDE.md has bloated. Propose moving path-scoped content into `.claude/rules/*.md` with `paths:` frontmatter so it only loads when relevant.
- **Total before first turn > 40%** → the session will autocompact early. Combination of the above.

## Output format

```
Context slice       | Tokens | % window | Status
--------------------|--------|----------|-------
System prompt       | …      | …        | ok
System tools        | …      | …        | ok
MCP tool desc       | …      | …        | ⚠ over 10%
Memory / CLAUDE.md  | …      | …        | ok
Skills              | …      | …        | ok
History / messages  | …      | …        | ok
```

Then, if any row is ⚠, suggest one concrete fix per row (not a generic "reduce context"). Reference the specific MCP servers, skill files, or memory files to target.

If everything is fine, say so in one line and stop.
