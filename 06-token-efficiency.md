# Project setup & CLAUDE.md

## Bootstrapping a new project

Order of operations:

1. `git init` and make a first empty commit.
2. `claude` → in the session, run `/init`. It generates a starter `CLAUDE.md` from what's in the repo.
3. **Immediately** replace the generated CLAUDE.md with the template in `templates/core/CLAUDE.md` and fill in the `<placeholders>`. The auto-generated one is a decent snapshot but rarely matches what you'd actually want to tell Claude.
4. Drop in `.claude/settings.json` (from `templates/core/dot-claude/settings.json`).
5. Append `templates/core/.gitignore.append` to your `.gitignore`.
6. Commit: `chore: add claude code scaffolding`.

## CLAUDE.md: what it is

CLAUDE.md is a markdown file at the project root (or `.claude/CLAUDE.md`) that is loaded into context at **every session start**. It's Claude's project-level memory. Keep it under 200 lines — anything larger starts degrading adherence, and every line costs tokens on every turn.

### Structure that works

The canonical pattern from the community:

- **WHY** — what this project exists to do. One paragraph.
- **WHAT** — stack, entry points, key modules. Bullet list.
- **HOW** — commands, conventions, git workflow. Bullet list.
- **Claude behavior rules** — plan first, small diffs, ask questions, test what you write.
- **Pointers** — `@docs/architecture.md`, `.claude/rules/`, etc.
- **Gotchas** — traps that aren't visible from the code.

The template in `templates/core/CLAUDE.md` follows this shape.

### Rules of thumb

- **Prefer `file:line` pointers over pasted code.** Instead of embedding a schema, say "See `src/models/user.ts:12`".
- **Front-load what Claude would get wrong.** If a naming convention is unusual, it goes near the top.
- **Test it by ablation.** Delete half your CLAUDE.md for a session. Did Claude do worse? If not, the deleted half was waste.

## Memory hierarchy

Claude Code loads memory from several locations. More specific wins:

| Scope | Path | Shared? |
|---|---|---|
| Enterprise | OS-specific (`/etc/claude-code/CLAUDE.md`, etc.) | Admin-controlled |
| User | `~/.claude/CLAUDE.md`, `~/.claude/rules/` | No — machine-local |
| Project | `./CLAUDE.md` or `./.claude/CLAUDE.md` | Yes — committed |
| Local | `./CLAUDE.local.md` | No — gitignored |

Additionally, **nested CLAUDE.md files in subdirectories lazy-load** when Claude reads files in that subtree. Good for dense domains (e.g., `src/billing/CLAUDE.md`).

### @imports

CLAUDE.md can import other files with `@path`:

```markdown
See @README.md for project overview.
Git workflow: @docs/git-workflow.md
```

Paths resolve relative to the importing file. Imports are expanded at launch and **do not save tokens** — they're just organizational. Depth capped at 5 hops.

## Path-scoped rules (`.claude/rules/`)

The killer feature for big projects. Put a `paths:` glob in frontmatter; the file only loads when Claude reads a matching file:

```markdown
---
paths: ["src/api/**", "**/*.controller.ts"]
---
# Backend rules
...
```

This is the single biggest token-efficiency lever. Use it heavily for anything that's scope-specific. See `templates/token-efficiency/dot-claude/rules/` for starters.

## Auto memory

Claude Code has auto-memory enabled by default (v2.1.59+). It saves notes to `~/.claude/projects/<project>/memory/MEMORY.md` across sessions — things it figured out during debugging, build commands, etc.

- Run `/memory` to view or edit.
- First 200 lines (or 25 KB) of MEMORY.md are injected into every session.
- Disable with `"autoMemoryEnabled": false` in settings if you want strict determinism.

## Personal notes with CLAUDE.local.md

For "reminders to myself that shouldn't be in the committed CLAUDE.md" — like "the prod DB is weird about dates". Gitignored by convention. Loaded alongside CLAUDE.md, appended after it, so your personal notes take precedence.

## AGENTS.md

The multi-tool-neutral equivalent that some teams use (Cursor, Cline, etc.). Claude Code doesn't read it directly, but you can bridge:

```markdown
@AGENTS.md

## Claude Code specifics
- Use plan mode for changes under `src/billing/`.
```

## Sanity checks

Run this quarterly:

1. `/memory` — review what's loaded. Anything stale?
2. Delete CLAUDE.md entirely, run a session, see what Claude gets wrong. Those are things your CLAUDE.md should cover.
3. Look for contradictions between rules. Claude will pick one arbitrarily.
4. Move universally-true things to CLAUDE.md, path-specific things to `.claude/rules/`.
