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
model: inherit                # or fable (CC 2.1.170+) | sonnet | opus | haiku | full-id
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
- **Subagents can spawn nested subagents — 3 levels below the main thread by default (CC ≥ 2.1.219; 2.1.172–2.1.216 allowed 5, 2.1.217–218 shipped nesting off).** Tune with `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; at the cap Claude Code withholds the Agent tool from the subagent. Prefer leaf designs anyway — use skills or chain through the main thread — so the architecture survives older CC and doesn't bury context behind deep subagent transcripts.
- **Subagents run in the background by default (CC ≥ 2.1.198)** with a narrower built-in tool set; their permission prompts surface in the main session. At most 20 run concurrently (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, 2.1.217+); the 21st spawn fails with an error that tells Claude not to retry.
- **Forks are the opposite of isolation.** `subagent_type: "fork"` (on by default since 2.1.232; `/subtask` from the prompt) inherits the whole conversation and prompt cache. Use a fork to continue *this* context elsewhere; use a named subagent for a specialist with its own prompt.
- Parent `bypassPermissions` or `acceptEdits` **overrides** any `permissionMode` set on the subagent.

### Parallel subagents

You can spawn several at once for independent work. Main thread synthesizes. Good for:
- Reviewing three files in parallel.
- Running docs generation + security review + code review side-by-side.

For sustained parallelism that exceeds context, use **agent teams** (separate sessions).

### Built-in subagents you get for free

- `Explore` (read-only) — fast codebase exploration. Since CC 2.1.198 it inherits the session model (capped at Opus) instead of always running on Haiku; define a project agent named `Explore` with `model: haiku` to pin it cheap.
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

Usually skip: "kitchen sink" servers exposing dozens of tools you won't use — not because of tokens (see below) but because every extra server is another process, another auth prompt, and more surface for the model to reach for the wrong tool.

### What MCP actually costs

**Tool search changed this, and older advice (including earlier versions of this
page) is now wrong.** Claude Code defers MCP tool schemas by default and pulls
them in on demand, so a heavy `.mcp.json` no longer front-loads its schemas into
every prompt. `alwaysLoad: true` opts a server out of that deferral — it is the
setting that brings the old cost back.

Measured on Claude Code 2.1.245 (Opus 5, one-turn session, four local stdio
servers advertising twelve tools each — 48 tools total):

| Session | Prompt tokens | MCP's share |
|---|---|---|
| No MCP servers | 26,665 | — |
| 4 servers, default (deferred) | 27,361 | +696 (~14 tokens/tool) |
| 4 servers with `alwaysLoad: true` | 40,993 | +14,328 (~298 tokens/tool) |

Deferral removes ~95% of the schema cost. Two consequences:

1. **Adding a server is cheap. Loading it eagerly is not.** Reach for
   `alwaysLoad` only when a server's tools are used in nearly every turn.
2. **Per-task profiles are no longer primarily a token lever.** What they still
   buy is real: fewer processes and auth prompts at startup, faster cold start,
   and a smaller blast radius — `--strict-mcp-config` means only the listed
   servers exist for that session. Choose a profile for those reasons.

Still worth doing regardless of tokens:

- **Only enable what you'll actually use this week.** Fewer servers, fewer ways
  for a turn to go sideways.
- **Scope to subagents** — put MCP servers in a subagent's frontmatter
  (`mcpServers:`) so they're only live while that agent runs.
- **Wrap heavy servers in narrow skills** — if a server exposes 30 tools and you
  use 3, a skill that calls those 3 is easier for the model to aim.

### Checking the cost

`/context` in an active session shows what's loaded, and it is the number to
trust for your own project — the table above is one synthetic shape, not a law.
The dominant line is the baseline itself (~26.7k tokens of system prompt and
built-in tools before any MCP server exists); no profile changes that. `/cost`
shows spend.

## Orchestration patterns

### Plan-then-execute (default)
Planning subagent builds the plan, main session executes step by step. Good for non-trivial changes.

### Fanout generation (`/infinite`)
A skill spawns N subagents that each produce one distinct variant of a spec. Main thread coordinates assignments via a directory snapshot + uniqueness directive so siblings don't collide. The `multi-agent` module ships this as `/infinite <spec-file> <output-dir> <count>` plus a `parallel-generator` subagent. Works well when slices are independent — exact opposite of tightly-coupled features (see `multi-agent-guardrails.md`).

### Review-while-editing
Main session edits; `code-reviewer` subagent runs in parallel after every commit. Catches drift early.

### Desktop + cloud
Local Claude Code for interactive work; Claude Code Web for long-running cloud jobs. Worktrees bridge the two. Useful for "run this large refactor while I go do something else." After both branches converge, use `/merge-worktrees` (ships in `multi-agent`) to integrate safely via a disposable branch.

### When to reach for a workflow instead

Dynamic workflows (`/workflows`) run a script Claude writes over many agents,
with control flow, structured output between stages, a token budget, resume
after failure, and a progress view. Prefer them for staged pipelines
(find → verify → synthesize), for fan-out whose results need merging or scoring,
and for anything that should survive an interruption. Hand-rolled batching —
including the `/infinite` skill the `multi-agent` module ships — is the right
shape only for N independent variants of one spec written to disjoint slots.

### Limits

- The main thread's context is still finite. Subagents help with verbosity but not with total information you're holding in your head.
- Parallel subagents that return detailed results still fill the parent. Prefer "ship a summary, not a transcript."
- Subagent nesting is capped — 3 levels below the main thread by default since CC 2.1.219 (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`). If you need 3+ levels, the design is usually still wrong — re-shape into a fanout or pipeline through the main thread, or a dynamic Workflow for fan-outs beyond a handful of workers.

## Recommendations

Start with:
- 3-4 subagents: `code-reviewer`, `test-runner`, `doc-writer`, `security-auditor`.
- 0-2 MCP servers: `git`, maybe `context7`.
- Skills first for workflows; subagents for specialists.

Add more only when you catch yourself repeating the same prompts or losing context to verbose outputs.
