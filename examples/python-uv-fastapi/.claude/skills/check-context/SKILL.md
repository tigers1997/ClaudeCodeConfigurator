---
name: check-context
description: Break down what's in the current context window and flag bloat. Use before long sessions or when autocompaction fires earlier than expected.
effort: minimal
allowed-tools: Bash(claude:*)
---

# Check the context budget

Run `/context` first (the built-in) and read the breakdown it prints. Then analyze the slices below and report whether any are out of bounds.

## Budget guardrails

Before the user types anything a session already carries the system prompt, built-in tool descriptions, CLAUDE.md, path-scoped rules and the skill listing. Measured on Claude Code 2.1.245 that floor was ~26.7k tokens with no MCP servers configured at all — that's the baseline to compare against, and no MCP profile changes it. MCP tool schemas are deferred by tool search unless a server sets `alwaysLoad: true`, so they should be a thin slice (~14 tokens/tool, versus ~298 when eagerly loaded).

Flag the following:

- **MCP tool descriptions > 10%** of the window → with deferral on this is nearly impossible, so suspect a server with `alwaysLoad: true` (or a build predating tool search). Recommend dropping `alwaysLoad` first. Per-task `.mcp.<profile>.json` files with `claude --mcp-config <path> --strict-mcp-config` (or `./claude-ctx <profile>`) remain the right move when the goal is *fewer connected servers* — startup time, auth prompts, blast radius — rather than fewer tokens.
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
