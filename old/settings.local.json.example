---
name: sync-docs
description: Inspect recent changes and update CLAUDE.md / .claude/rules/ with anything new worth remembering.
allowed-tools: Read Write Edit Grep Glob Bash(git log:*) Bash(git diff:*)
---

# Sync docs to recent work

## Context
- Commits since last doc update: !`git log --since='7 days ago' --oneline`
- Files most recently changed: !`git log --since='7 days ago' --name-only --pretty=format: | sort -u | head -40`

## Your task

1. Read `CLAUDE.md` and every file under `.claude/rules/`.
2. Skim the commits and changed files. Identify conventions, traps, or architecture choices introduced that aren't yet captured.
3. Propose updates as a diff, per file:
   - `CLAUDE.md` — add if it's universally relevant (applies to the whole repo).
   - `.claude/rules/<scope>.md` — add if it's path-scoped. Create a new rules file with a `paths:` frontmatter if needed.
   - **Never duplicate**. If a rule already covers it, refine the existing one.
4. Keep `CLAUDE.md` under 200 lines. If a proposed addition pushes it over, move something else to a rules file first.
5. Ask before writing. Show the proposed diff and wait.

### What counts as "worth remembering"
- Naming or structure conventions now visible in 2+ files.
- Commands or scripts that were non-obvious to discover.
- Gotchas hit during recent debugging.
- Dependencies or integrations added.
- Non-obvious file:line pointers that unlock context.
