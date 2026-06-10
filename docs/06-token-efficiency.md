# Token efficiency

Context is a fixed resource. Every turn starts with whatever your configuration forces Claude to load. The difference between a well-configured project and a poorly configured one is often 10-20k tokens of baseline cost — which translates directly into slower, more expensive, more error-prone sessions.

## The cost model, simplified

Every session starts with:

1. **System prompt** — Claude Code's built-in prompt. Fixed cost, can't touch.
2. **CLAUDE.md** (+ concatenated nested ones) — your doing. **Main lever.**
3. **Imported files via `@path`** — expand at launch. Same cost as if inlined.
4. **Auto-memory** — first 200 lines / 25 KB of MEMORY.md. Toggleable.
5. **MCP tool definitions** — every enabled server's tool schemas. **Hidden fat.**
6. **Available subagents' descriptions** — short, but they add up if you have many.
7. **Skills with `disable-model-invocation: false`** — descriptions only, not bodies.

After that, each turn adds:

- Tool output you let Claude see.
- File content Claude reads.
- Conversation history, compacted as it grows.

## The six big levers

### 1. Keep CLAUDE.md lean
- **Target: under 200 lines.** Community consensus.
- No pasted code — use `file:line` pointers.
- No long lists of things that only apply in one part of the repo — move to `.claude/rules/`.
- Quarterly prune: delete anything you can't justify.

### 2. Use `.claude/rules/` aggressively
Path-scoped rules only load when Claude reads matching files. Zero cost otherwise. Move anything domain-specific here (frontend rules, test rules, DB rules). See `templates/token-efficiency/dot-claude/rules/` for starters.

### 3. Audit MCP servers quarterly
Run `/context` in a session. Count the tokens eaten by MCP tool definitions. If a server exposes 30 tools and you use 3, either:
- Remove it and call those 3 as Bash commands.
- Scope it to a subagent that needs it.
- Replace it with a targeted skill.

### 4. Prefer skills over subagents for light work
Subagents have their own system prompts and fresh context windows. That's great for isolation, bad for speed. If a task is under a minute of main-thread work, a skill with `context: main` is cheaper.

Use `context: fork` only when the work generates a lot of tool output you don't want polluting the main thread.

### 5. Compact proactively
- `/compact` summarizes the conversation. Run it yourself when you notice latency or before a handoff, rather than waiting for auto-compaction at ~95%.
- Use the `PreCompact` hook to save a durable snapshot before state is lost.

### 6. Scoped reads
Teach Claude (in CLAUDE.md rules) to prefer `grep` / structured search over `cat entire-file.md`. Read only what's needed.

## Context bloat: the hidden problem

Common causes:

- **Over-general MCP config.** A broad server with many tools burns tokens every session whether you use it or not.
- **Fat CLAUDE.md.** Every subdirectory loads its nested CLAUDE.md too when Claude reads files there. If every subdir has a 300-line CLAUDE.md, you're spending hugely.
- **Eager skills with `disable-model-invocation: false`.** Claude scans skill descriptions at every turn to decide whether to invoke. Many skills with long descriptions = real token cost.
- **Auto-memory gone wild.** `/memory` shows what's been saved. If MEMORY.md has years of stale notes, prune it or disable auto-memory.

## How to measure

Every session:
- `/context` → see what's loaded (CLAUDE.md, rules, tools, memory).
- `/cost` → see spend-to-date.

Do a "context budget review" monthly:
- Open a fresh session in your project.
- Run `/context`.
- Write down the numbers: CLAUDE.md lines, rules files active, MCP tool definitions, auto-memory size.
- Compare to last month. Trend matters more than absolute value.

## Opinionated defaults for a single-developer project

- CLAUDE.md: 120-180 lines.
- `.claude/rules/`: 4-8 files, 50-100 lines each.
- MCP servers: 0-2 enabled. Start with zero; add one when you catch yourself needing it weekly.
- Auto-memory: on, but prune MEMORY.md quarterly.
- Subagents: 3-5 defined, most inheriting the main model.
- Skills: 5-10. If you have more, you're probably using skills for things CLAUDE.md could just tell Claude once.

## The model-choice lever

- Haiku for cheap, fast, read-only work — great for `Explore`, grep-style research, the `doc-writer` subagent.
- Fable 5 (`fable`, CC 2.1.170+) for day-to-day edits and reviews — the scaffolded default. It is the most capable model and the priciest; the rest of this doc's levers (Haiku subagents, narrowing flags, reset rhythm) are what keep that affordable.
- Opus for high-stakes review and deep refactors on Claude Code older than 2.1.170, or where your org's plan doesn't include Fable 5.

Most sessions can run primarily on Fable 5 with Haiku subagents for reads. On older Claude Code the `fable` alias isn't selectable — drop the project back to `sonnet` via `.claude/settings.local.json` (the example file ships the stub).

### Effort level (Pro/Max only)

Since Claude Code 2.1.117, Pro/Max subscribers on Opus 4.6 and Sonnet 4.6 default to `effort: high` (was `medium`). The default is already tuned — do **not** manually downgrade to `medium` thinking you're saving tokens. You're not; you're getting a less capable response for the same budget. If you want cheaper, drop to Haiku or use a lighter model. Reserve `effort: minimal` for skills that are mechanical (e.g. `/sync-docs`, `/check-context`, `/session-retro` — the `eff_effort_minimal` toggle stamps this automatically on those skills' frontmatter).

## When you hit the context wall mid-session

1. `/compact` — don't wait for auto-compaction.
2. Check `/context`. Is there a subagent chatting a lot? A file you accidentally pasted in?
3. Start a new session if the task is now ambiguous due to compression. Carry forward the state deliberately via a short pasted summary, not a full transcript.
4. Take the lesson: something was too verbose. Adjust your hooks (less `additionalContext`), prune CLAUDE.md, or split the task.

## Quick-reference checklist

- [ ] CLAUDE.md is under 200 lines.
- [ ] Path-scoped rules handle all per-domain guidance.
- [ ] `/context` shows MCP tool definitions under ~3k tokens.
- [ ] No subagent descriptions over ~50 words.
- [ ] `PreCompact` hook snapshots session state.
- [ ] `/cost` and `/context` checked at least weekly.
- [ ] Auto-memory MEMORY.md pruned this quarter.
