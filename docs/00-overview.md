# Claude Code Setup — Overview

A practical reference for running Claude Code on single-user, git-enabled projects. Curated from the official Anthropic docs at `code.claude.com`, the `anthropics/claude-code` repo, community best-practice posts, and working-team patterns.

## How to use this kit

Three ways, pick one:

1. **The configurator CLI** — run `cc-configure` in a target project and pick modules interactively. Stack presets prefill stack-appropriate defaults; preflight checks catch schema drift before files are written. Recommended. See the top-level `README.md` for install + flags.
2. **Hand-copy from `templates/`** — every module is a real file. Copy what you want into your project. `templates/INDEX.md` maps template paths to target paths.
3. **Read the docs here first** — the numbered docs below explain the *why* behind each lever so you can adapt them to your project.

## The mental model

Claude Code is an agent loop with six levers you can pull:

| Lever | What it does | Where it lives |
|---|---|---|
| **Memory** | Persistent instructions loaded at session start or on demand | `CLAUDE.md`, `.claude/rules/*.md`, nested `CLAUDE.md` in subdirs |
| **Settings** | Model, permissions, env vars, hook wiring | `.claude/settings.json` (+ `.local.json`) |
| **Slash commands / Skills** | Reusable prompts invoked with `/name` | `.claude/skills/<name>/SKILL.md` |
| **Hooks** | Deterministic scripts on lifecycle events | `.claude/hooks/*.sh` wired in settings |
| **Subagents** | Context-isolated specialist agents | `.claude/agents/<name>.md` |
| **MCP** | External tools/data exposed via MCP servers | `.mcp.json` (+ optional per-task `.mcp.<profile>.json`) |

Everything in this kit is a structured choice about which levers to pull and how.

## The numbered docs

1. **[Project setup & CLAUDE.md](01-project-setup.md)** — starting a new repo, writing memory that pays for itself
2. **[Git workflow](02-git-workflow.md)** — single-dev branches, commits, worktrees
3. **[Slash commands & hooks](03-commands-and-hooks.md)** — automate the parts you do every day
4. **[Subagents, MCP & orchestration](04-subagents-mcp-orchestration.md)** — when to reach for each
5. **[Safety, permissions & review](05-safety-permissions.md)** — keeping the agent on rails
6. **[Token efficiency](06-token-efficiency.md)** — making every session cheap and sharp
7. **[Memory hierarchy](08-memory-hierarchy.md)** — the 5-level ladder (enterprise → user → project → path-scoped rules → local) and where each type of rule belongs
8. **[Retrofit guide](09-retrofit-guide.md)** — what belongs in CLAUDE.md vs. elsewhere; how to triage an existing complex CLAUDE.md before running `cc-configure`; what the configurator does on a retrofit run; how to resolve staged conflicts (manual or via `/retrofit`)

(`07-backlog.md` is local-only, gitignored — project roadmap notes.)

## Modules → docs mapping

Which modules operationalize which docs:

| Module | Operationalizes |
|---|---|
| `core` | Doc 01 (CLAUDE.md from your form answers, "Working with Claude" collaboration section) |
| `safety` | Doc 05 (PreToolUse hooks, `disableBypassPermissionsMode`) |
| `git-workflow` | Doc 02 (format-on-write, Stop-hook checks) |
| `token-efficiency` + `token-efficiency-pro` | Doc 06 (path-scoped rules, bash-output caps, PreCompact snapshots) |
| `commands-core` | Doc 03 (eight skills: plan, review, commit, ship, sync-docs, check-context, session-retro, verify-setup) |
| `agents` | Doc 04 (four specialists: code-reviewer, test-runner, doc-writer, security-auditor) |
| `mcp` | Doc 04 (.mcp.json + per-task profiles + `./claude-ctx` wrapper) |
| `multi-agent` | Doc 04 (guardrails rule, `/merge-worktrees`, `/infinite`, `parallel-generator` subagent) |
| `github-actions` | Doc 03 (workflow triggered on `@claude` mentions) |
| `ui` | Doc 06 (statusline + "plan" output style) |
| `lockdown` | Doc 05 (`DISABLE_UPDATES=1` for air-gapped environments) |
| `experiments-memory` | Doc 08 (nested `memory/experiments/CLAUDE.md` — zero-cost lazy loading) |

## Guiding principles

- **Plan → small diff → tests → review.** Every non-trivial task follows this loop.
- **Context is infrastructure.** Treat `CLAUDE.md` like a Makefile: short, precise, versioned.
- **Prefer pointers to pasted content.** `file:line` references beat inline code blocks.
- **Determinism at the edges.** Use hooks for anything that shouldn't depend on model judgment (formatting, safety blocks, secret scans).
- **Isolate for parallelism.** Subagents and worktrees let you run work in parallel without context bloat.
- **Measure context cost.** Run `/context` and `/cost`. Kill anything you're paying for and don't use.
- **Verify before shipping.** `cc-configure --check` in CI catches template drift; `/verify-setup` audits an already-scaffolded project against best practices.

## Versions this kit assumes

- Claude Code ≥ 2.1.59 (auto-memory, modern frontmatter). Some optional polish needs 2.1.119+ (statusline `effort.level` / `thinking.enabled`).
- Git ≥ 2.40 (worktrees).
- Python ≥ 3.8 for `cc-configure` itself (stdlib only).

## Sources

- `https://code.claude.com/docs/en/` — hooks, sub-agents, skills, memory, MCP, permissions, settings
- `https://github.com/anthropics/claude-code` — CHANGELOG, canonical examples; authoritative when docs and book-style references disagree
- `https://www.humanlayer.dev/blog/writing-a-good-claude-md`
