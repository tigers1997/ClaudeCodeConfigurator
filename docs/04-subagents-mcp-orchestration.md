# Subagents, MCP & orchestration

Three tools for scaling work without drowning your main context. Pick the right one for the job.

## The decision tree

- Need a **specialist with its own system prompt and context window**? → **Subagent**.
- Need **external data or actions** (GitHub API, DB, browser)? → **MCP server**.
- Need an **opinionated workflow** that's scoped to a task? → **Skill** (see previous doc).

These compose. A subagent can use MCP servers. A skill can fork into a subagent that uses MCP.

## Subagents

### What they are

A subagent is a Markdown file in `.claude/agents/<name>.md` (project) or `~/.claude/agents/<name>.md` (user). Its body becomes the system prompt for an isolated context window with its own tools, model, and permissions.

### When to use

- **Read-heavy review**: code review, security audit, architecture review. The subagent reads a lot; only its summary comes back to you.
- **Expensive analysis**: running tests, inspecting logs, grep-heavy searches — anything that generates verbose tool output you don't want in the main transcript.
- **Parallel independent tasks**: refactor three files at once; the main session coordinates and merges.

### When NOT to use

- Short, interactive iteration — subagents have latency; they start fresh and can't ask clarifying questions mid-turn.
- Tasks that need the full conversation context — subagents don't inherit it.
- Anything under ~30 seconds of work in the main thread.

### Frontmatter essentials

```yaml
---
name: code-reviewer           # required, lowercase-hyphens
description: ...              # required; shapes when Claude auto-invokes
tools: Read, Grep, Glob, Bash # omit to inherit all; be stingy
model: inherit                # or sonnet | opus | haiku | full-id
permissionMode: default       # plan | acceptEdits | auto | dontAsk | bypassPermissions
color: purple                 # optional UI hint
isolation: worktree           # optional — run in a temp git worktree
---
```

Only `name` and `description` are required. See `templates/agents/` for four realistic starters.

### Invocation

- **Automatic** — Claude reads your request, matches against `description` fields, picks a subagent. Include "use proactively" in descriptions you want auto-invoked.
- **Explicit natural language** — "use the code-reviewer subagent to look at this diff".
- **@-mention** — `@"code-reviewer (agent)"`.
- **Session-wide** — `claude --agent code-reviewer` (whole session runs with that agent's prompt/tools).
- **Ephemeral JSON** — `claude --agents '{"foo": {...}}'`.

### Context hygiene

- Each subagent starts with its own system prompt + minimal env info. **No inherited conversation**.
- Only the subagent's final response returns to the parent. Verbose tool output stays in the subagent's transcript.
- **Subagents cannot spawn other subagents.** Design around this — use skills or chain through the main thread.
- Parent `bypassPermissions` or `acceptEdits` **overrides** any `permissionMode` set on the subagent.

### Parallel subagents

You can spawn several at once for independent work. Main thread synthesizes. Good for:
- Reviewing three files in parallel.
- Running docs generation + security review + code review side-by-side.

For sustained parallelism that exceeds context, use **agent teams** (separate sessions).

### Built-in subagents you get for free

- `Explore` (Haiku, read-only) — fast codebase exploration.
- `Plan` (inherits, read-only) — structured planning.
- `general-purpose` — default catch-all.
- `statusline-setup`.
- `Claude Code Guide`.

Prefer these over custom ones for their use cases.

## MCP (Model Context Protocol)

### What it is

A standard protocol for exposing tools and data to LLM-based clients. You run an MCP server; Claude Code connects to it; its tools appear in the agent's toolbox.

### Scopes

| Scope | Config location | When |
|---|---|---|
| User | `claude mcp add --scope user` | Personal, cross-project (your docs search, your bookmarks) |
| Project | `.mcp.json` at repo root | Required by the project. Commit it. |
| Local | `claude mcp add --scope local` | Machine-specific override (different token, different path). Gitignored. |

Precedence on name collision: **local > project > user**.

### Picks for a single developer

High value, low cost:
- **filesystem** — explicit sandboxed FS access. Pair with narrow `allowedTools`.
- **git** — structured git operations beyond Bash.

Situationally valuable:
- **github** — if Claude should handle issues and PRs.
- **playwright** — any frontend project.
- **context7** — live library docs lookup. Stops hallucinated APIs.

Usually skip: "kitchen sink" servers exposing dozens of tools you won't use. Every tool definition costs tokens on every session start.

### Context bloat is real

Every MCP tool is a chunk of JSON schema loaded at session start. A heavy `.mcp.json` can burn thousands of tokens before you type anything. Mitigations:

1. **Only enable what you'll actually use this week.**
2. **Scope to subagents** — put MCP servers in a subagent's frontmatter (`mcpServers:`) so they only load for that agent.
3. **Wrap heavy servers in narrow slash commands** — if a server exposes 30 tools and you use 3, write a skill that calls those 3.

### Checking the cost

`/context` in an active session shows what's loaded. `/cost` shows spend. Use both.

## Orchestration patterns

### Plan-then-execute (default)
Planning subagent builds the plan, main session executes step by step. Good for non-trivial changes.

### Infinite agentic loop
A skill spawns N subagents that each execute one slice of a plan. Main thread iterates on results. Works well when slices are independent.

### Review-while-editing
Main session edits; `code-reviewer` subagent runs in parallel after every commit. Catches drift early.

### Desktop + cloud (Ch 10)
Local Claude Code for interactive work; Claude Code Web for long-running cloud jobs. Worktrees bridge the two. Useful for "run this large refactor while I go do something else."

### Limits

- The main thread's context is still finite. Subagents help with verbosity but not with total information you're holding in your head.
- Parallel subagents that return detailed results still fill the parent. Prefer "ship a summary, not a transcript."
- Subagents can't spawn subagents. If you need 3 levels, you're designing wrong.

## Recommendations

Start with:
- 3-4 subagents: `code-reviewer`, `test-runner`, `doc-writer`, `security-auditor`.
- 0-2 MCP servers: `git`, maybe `context7`.
- Skills first for workflows; subagents for specialists.

Add more only when you catch yourself repeating the same prompts or losing context to verbose outputs.
