# MCP servers cookbook

## Scope cheat sheet
| Scope | File | When to use |
|---|---|---|
| **user** | `~/.claude.json` (via `claude mcp add --scope user`) | Personal servers that work across all your projects (e.g. your docs search). |
| **project** | `.mcp.json` at repo root | Servers the project *requires*. Commit it. |
| **local** | `.claude.json` or `claude mcp add --scope local` | Machine-specific overrides (e.g. different token, different path). Gitignored. |

Precedence when names collide: **local > project > user**.

## Add / remove via CLI
```bash
# Project scope, stdio
claude mcp add my-server --scope project -- npx -y @modelcontextprotocol/server-filesystem /repo

# List what's wired
claude mcp list

# Remove
claude mcp remove my-server
```

## Practical picks for a single developer

### Always useful
- **filesystem** — explicit sandboxed file access; pairs well with tight `allowedTools` on subagents.
- **git** — git operations beyond Bash (blame, show, log with structured output).

### Useful when relevant
- **github** — if the project is on GitHub and you want Claude to handle issues/PRs inline.
- **playwright** — any frontend work where you'd otherwise ask Claude to describe what it changed.
- **context7** — live library docs lookup. Saves Claude from guessing API shapes.
- **postgres** / **sqlite** — read-only DB introspection when Claude is writing queries.

### Usually skip
- "Kitchen sink" servers that expose dozens of tools you'll never call. Each tool definition burns context.

## Context hygiene
- **Every MCP server costs tokens** on session start (tool definitions). Only enable what you'll use this week.
- Use per-subagent `mcpServers` frontmatter to scope a heavy server to just the agent that needs it.
- When iterating on MCP choice, run `/context` to see the cost.
- If a server exposes 30 tools and you use 3, write a narrow slash-command wrapper instead.

## Gotchas
- Some servers need env vars. Put tokens in your shell env or `1Password` / `op run`, not in `.mcp.json`.
- Windows paths in `args` need forward slashes or escaped backslashes.
- Restart Claude Code after editing `.mcp.json` for changes to take effect.
