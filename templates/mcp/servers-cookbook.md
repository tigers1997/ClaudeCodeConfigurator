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

## Per-task profiles with `claude-ctx`

A fresh session with 4 MCP servers loaded burns ~49% of a 100k context window before you type anything (system prompt ~2.2k + system tools ~12k + MCP tool descriptions ~37k). For tasks that don't need those servers, scope per-task instead of loading the full default set.

Profiles live at `.mcp.<name>.json` in the project root. Three are shipped by default:

| Profile | Contents | When to use |
|---|---|---|
| `research` | context7 | Reading code you didn't write, investigating APIs, needing accurate library docs |
| `frontend` | playwright | Browser/UI work, regression checks, visual verification |
| `minimal` | (none) | Pure writing or editing sessions — demonstrates the scope savings cleanly |

Run via the shipped wrapper:
```bash
./claude-ctx research          # claude --mcp-config .mcp.research.json --strict-mcp-config
./claude-ctx frontend --resume # any extra args pass through to claude
./claude-ctx                   # no arg -> lists available profiles
```

`--strict-mcp-config` tells Claude Code to ignore the default MCP hierarchy (user/project/local) and only load what's in the specified file. This is the key flag — without it, the per-task file *adds* to the defaults rather than replacing them.

Create your own profile by copying one of the starters and dropping in the servers you actually need for that task class.
