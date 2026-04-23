---
# Frontmatter that never matches anything — this is a guide, not an active rule.
paths: ".claude/rules/__never-match__"
---
# How to use .claude/rules/

Path-scoped rules only load into context when Claude reads files that match
the `paths` glob. This is the single biggest token-efficiency lever in Claude
Code. Use it aggressively.

## Authoring checklist
1. One file per domain (frontend, backend, tests, infra, db, auth…).
2. Each file has frontmatter with a `paths:` glob.
3. Keep bodies short — ~50-100 lines. Pointers, not essays.
4. `paths` supports glob syntax. Examples:
   - `src/web/**` — single subtree
   - `src/api/**/*.{ts,py}` — restrict by extension
   - `["src/db/**", "migrations/**"]` — multiple globs
5. Prefer rules over CLAUDE.md for anything that isn't universally relevant.

## Why this matters
- CLAUDE.md loads into **every** turn. Keep it under 200 lines.
- Rules load **only when touching matching files**. No cost otherwise.
- Nested `CLAUDE.md` files in subdirectories also lazy-load — use those when
  the scope is a directory, not a pattern.

## When to promote to CLAUDE.md
- The rule applies to the whole project (e.g. commit conventions).
- Forgetting it would cause repeated, expensive mistakes.
- It's referenced by Claude more than once per session.
