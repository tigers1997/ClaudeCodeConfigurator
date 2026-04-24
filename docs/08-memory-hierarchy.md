# The 5-level memory hierarchy

Claude Code loads context from five scopes, from least-specific to most-specific. Understanding where a rule *should* live is more useful than piling everything into `CLAUDE.md`.

## The ladder

| # | Scope | Location | Loaded when | Commit? |
|---|---|---|---|---|
| L1 | **Enterprise / managed** | Org-managed settings distribution | Always, and no project can override it | N/A — IT controls it |
| L2 | **User** | `~/.claude/CLAUDE.md` (+ `~/.claude/rules/*.md`) | Every session you start, regardless of project | No — lives on your machine |
| L3 | **Project** | `./CLAUDE.md` | Every session inside this repo | **Yes** — share with collaborators |
| L4 | **Path-scoped project rules** | `./.claude/rules/*.md` with `paths:` frontmatter | Only when Claude reads files matching the glob | **Yes** — shared + versioned |
| L5 | **Local / personal** | `./CLAUDE.local.md` | Every session in this repo, for you only | No — gitignored |

More-specific scopes override less-specific when they conflict on the same topic.

## What belongs where

### L3 — `./CLAUDE.md`

Project-wide truth that every contributor should see.

- What the project is, its WHY / WHAT / HOW.
- Core commands: install, dev, test, lint, build.
- Architecture conventions that apply across the whole repo.
- Collaboration style you want with Claude (the "Working with Claude" section).

Soft cap: **200 lines.** When it crosses, move path-specific content down to L4.

### L4 — `./.claude/rules/*.md`

Path-scoped rules that only load when relevant. **The single biggest token-efficiency lever in Claude Code.** Use it aggressively.

Each file has frontmatter:
```yaml
---
paths: "src/frontend/**"
---
```

Good candidates for L4:
- Frontend-only conventions (`paths: "src/frontend/**"`).
- Backend-only patterns (`paths: "src/api/**"`).
- Test-file conventions (`paths: "**/*.test.ts"`).
- Database migration rules (`paths: "migrations/**"`).
- Infrastructure-as-code style (`paths: "infra/**"`).

Keep each file short — pointers and file:line references, not essays. If a rule applies everywhere, it belongs in `CLAUDE.md`, not in a rules file with `paths: "**"`.

### L5 — `./CLAUDE.local.md`

Your personal overrides and scratchpad. Gitignored by the scaffolded `.gitignore`. Good for:

- "Don't try to run the integration tests on my machine — Docker isn't set up."
- "Preferred shortcuts that only I use."
- WIP notes you don't want to share yet.

### L2 — `~/.claude/CLAUDE.md`

Loads in *every* session, across all your projects. Good for:

- "When handling code related to dependencies, always prioritize Sonatype MCP tools."
- "Use Haiku for file reading, Opus for architecture decisions."
- General-purpose preferences that aren't project-specific.

### L1 — Enterprise

If your org ships managed Claude Code settings, L1 wins over L2–L5 on anything it asserts. You can't override from inside the project.

## How to decide where a rule goes

Ask in order:

1. **Does this rule apply to every project I work on?** → L2 (user).
2. **Does it apply to every contributor on this project?** → L3 (CLAUDE.md) if universal, L4 (rules with `paths:`) if it only applies to certain directories.
3. **Is it just for me on this project?** → L5 (CLAUDE.local.md).
4. **Is it just for me across all projects?** → L2 (user).

If you find yourself pasting the same text into two levels, one of them is wrong.

## Auto-memory and MEMORY.md

Claude Code's auto-memory system (`~/.claude/projects/<project>/memory/`) is a separate mechanism that indexes durable facts via `MEMORY.md`. It's not in the 5-level ladder — it complements it. Use auto-memory for facts that should persist *across* conversations in the same project (preferences, decisions, reference pointers). Use L1–L5 for *context* that loads into each new session.

## Related

- `docs/06-token-efficiency.md` — why this hierarchy matters for context budget.
- `templates/token-efficiency/dot-claude/rules/_scoping-guide.md` — how to write a good `paths:` glob.
