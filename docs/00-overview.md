# Claude Code Setup — Overview

A practical, research-backed reference for running Claude Code on single-user, git-enabled projects. Curated from Eden Marco's *Agentic Coding with Claude Code* (Packt, March 2026), the current Anthropic docs at docs.claude.com / code.claude.com, and community best-practice posts.

## How to use this kit

Three ways, pick one:

1. **The configurator** (`configurator.html`) — interactive picker. Choose modules, download a setup script that creates the file infrastructure in a target folder. Recommended.
2. **Hand-copy from `templates/`** — every module is a real file. Copy the ones you want into your project. See `templates/INDEX.md` for the path mapping.
3. **Read the docs here first** — the six numbered docs below explain the *why* behind each module so you can adapt them.

## The mental model

Claude Code is an agent loop with six levers you can pull:

| Lever | What it does | Where it lives |
|---|---|---|
| **Memory** | Persistent instructions loaded at session start or on demand | `CLAUDE.md`, `.claude/rules/*.md` |
| **Settings** | Model, permissions, env vars, hook wiring | `.claude/settings.json` (+ `.local.json`) |
| **Slash commands / Skills** | Reusable prompts you invoke with `/name` | `.claude/skills/<name>/SKILL.md` |
| **Hooks** | Deterministic scripts on lifecycle events | `.claude/hooks/*.sh` wired in settings |
| **Subagents** | Context-isolated specialist agents | `.claude/agents/<name>.md` |
| **MCP** | External tools/data exposed via MCP servers | `.mcp.json` |

Everything in this kit is a structured choice about which levers to pull and how.

## The six focus areas

1. **[Project setup & CLAUDE.md](01-project-setup.md)** — starting a new repo, writing memory that pays for itself
2. **[Git workflow](02-git-workflow.md)** — single-dev branches, commits, worktrees
3. **[Slash commands & hooks](03-commands-and-hooks.md)** — automate the parts you do every day
4. **[Subagents, MCP & orchestration](04-subagents-mcp-orchestration.md)** — when to reach for each
5. **[Safety, permissions & review](05-safety-permissions.md)** — keeping the agent on rails
6. **[Token efficiency](06-token-efficiency.md)** — making every session cheap and sharp

## Guiding principles

- **Plan → small diff → tests → review.** Every non-trivial task follows this loop.
- **Context is infrastructure.** Treat `CLAUDE.md` like a Makefile: short, precise, versioned.
- **Prefer pointers to pasted content.** `file:line` references beat inline code blocks.
- **Determinism at the edges.** Use hooks for anything that shouldn't depend on model judgment (formatting, safety blocks, secret scans).
- **Isolate for parallelism.** Subagents and worktrees let you run work in parallel without context bloat.
- **Measure context cost.** Run `/context` and `/cost`. Kill anything you're paying for and don't use.

## Versions this kit assumes

- Claude Code ≥ 2.1.59 (auto-memory, modern frontmatter)
- Git ≥ 2.40 (worktrees)
- Node 20 or Python 3.12 for the example tooling

## Sources


- `https://code.claude.com/docs/en/` — hooks, sub-agents, skills, memory
- `https://www.humanlayer.dev/blog/writing-a-good-claude-md`
- `https://01.me/en/2025/12/context-engineering-from-claude/`
