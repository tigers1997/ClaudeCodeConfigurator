# {{project_name}}

{{one_line_description}}

<!--
CLAUDE.md — project memory loaded at every session start.
Target: under 200 lines. Keep WHY/WHAT/HOW tight. Prefer file:line pointers
over pasted code. Put path-scoped detail in .claude/rules/*.md instead.
-->

**Repo:** {{repo_url}}
**Default branch:** `{{default_branch}}`
**License:** {{license}}

## WHY — what this project exists to do

{{goals}}

### Non-goals
{{non_goals}}

## WHAT — the shape of the system

- **Language / runtime:** {{language}}
- **Framework:** {{framework}}
- **Package manager:** {{package_manager}}
- **Test runner:** {{test_runner}}
- **Formatter:** {{formatter}}
- **Typechecker:** {{typechecker}}
- **Build tool:** {{build_tool}}
- **Data:** {{database}}
- **Deployment target:** {{deployment}}

## HOW — the conventions that matter

### Commands
- Install: `{{cmd_install}}`
- Dev: `{{cmd_dev}}`
- Test: `{{cmd_test}}`
- Lint: `{{cmd_lint}}`
- Typecheck: `{{cmd_typecheck}}`
- Build: `{{cmd_build}}`

### Code style
- **Indent:** {{indent}}
- **Max line length:** {{max_line}}
- **Quote style:** {{quote_style}}
- **Naming:** {{naming}}
- File size soft-cap: 300 lines. Split when crossed.
- Lint errors are build failures. Do not disable rules without a linked issue.
- Prefer pure functions + explicit types. Avoid global mutable state.

### Testing
- **Philosophy:** {{test_philosophy}}
- Every new feature ships with tests. Integration tests for endpoints and flows.
- Run the test suite before committing.

### Git workflow
- **Commit style:** {{commit_style}}
- **Branch strategy:** {{branch_strategy}}
- One logical change per commit. Never commit directly to `{{default_branch}}`.
- Before commit: format → lint → typecheck → test. All green.
- Use `git worktree add ../<name> -b feat/<name>` for parallel experiments.

### Repo bootstrap
The cc-configure scaffold makes assumptions about what to track vs. ignore. Honor them when first-committing a new project (`git init` + first `git add`) or when restructuring `.gitignore`:

- **Commit:** `CLAUDE.md`, `.claude/` (agents, hooks, skills, rules, settings.json, output-styles), `.mcp*.json`, `claude-ctx` if present, project source.
- **Gitignore by default:** `.claude/settings.local.json` (machine-local), `.claude/logs/`, `.claude/.frozen` / `.guarded` / `.careful` (transient state cleared by SessionStart), `.claude-config.json` (configurator working-state). cc-configure appends the `# --- Claude Code ---` block to `.gitignore` automatically — if you rewrite or replace `.gitignore`, preserve that block (or rerun `cc-configure --retrofit` to re-append it).
- **Nested upstream clones** (vendored deps, fork wrappers) should be gitignored and keep their own `.git/` — don't try to nest two repos in one tree. List the subdir in `.gitignore` *above* the Claude Code block.

## Design features

- **Architecture:** {{architecture}}
- **State management:** {{state_mgmt}}
- **API style:** {{api_style}}
- **Auth:** {{auth}}
- **Observability:** {{observability}}

## Common instructions (always apply)

{{common_instructions}}

## Known gotchas

{{known_gotchas}}

## External tools Claude may use

- **CLIs available:** {{clis}}
- **MCP servers enabled:** {{mcps}}

## Working with Claude (collaboration patterns)

These are *how the human should drive*, not rules Claude enforces. Distilled from teams that use Claude Code in production.

- **Task classification.** Decide up-front: is this peripheral/prototyping work (auto-accept edits, let Claude run) or core logic (synchronous review, every edit inspected)? Don't let the mode drift mid-session.
- **Slot-machine style for long runs.** Commit your state, let Claude run autonomously for ~30 minutes, then either accept the result or `git reset --hard` and start fresh. Wrestling a bad run to success almost always loses to a clean restart.
- **Commit as you go.** Ask Claude to commit incrementally during work, not at the end. Smaller commits = cheaper rewinds and less context bloat from a giant pending diff.
- **Self-sufficient loops.** Wire `test`/`lint`/`typecheck` into a `Stop` or `PostToolUse` hook so Claude runs them automatically and catches its own mistakes — no need for you to referee every turn.
- **Spec-driven restart.** For features that span many files: first run `/plan` to produce a spec, save it to `spec/<feature>.md`, then **start a fresh session** and implement from `@spec/<feature>.md`. The restart matters — a clean context produces sharper code than a planning-polluted one.

### Tool-calling guardrails (fill these in as you observe quirks on this project)

- <!-- e.g. "Run `pytest tests/`, not `pytest` alone — it picks up stale compiled files" -->
- <!-- e.g. "Don't `cd` into subdirs; all commands run from repo root" -->
- <!-- add more as model quirks surface -->

## Claude Code behavior rules

- **Plan before diff.** For any change touching more than one file, enter plan mode (Shift+Tab twice) and show a plan before editing. Plan mode is read-only and the cheapest turn-for-turn.
- **Small diffs.** Prefer small, reviewable commits. If a task grows, split it.
- **Ask, don't assume.** When requirements are ambiguous, ask one question rather than guessing.
- **Test what you write.** If you add logic, add or update a test in the same turn.
- **No silent writes.** Summarize every file you create or edit at the end of the turn.
- **Stay inside the repo.** Do not `cd` outside the project; do not touch `.git/`, `.env*`, or credential files.

{{efficiency_rules}}

