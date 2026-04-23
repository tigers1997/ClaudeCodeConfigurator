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

## Claude Code behavior rules

- **Plan before diff.** For any change touching more than one file, enter plan mode (Shift+Tab twice) and show a plan before editing. Plan mode is read-only and the cheapest turn-for-turn.
- **Small diffs.** Prefer small, reviewable commits. If a task grows, split it.
- **Ask, don't assume.** When requirements are ambiguous, ask one question rather than guessing.
- **Test what you write.** If you add logic, add or update a test in the same turn.
- **No silent writes.** Summarize every file you create or edit at the end of the turn.
- **Stay inside the repo.** Do not `cd` outside the project; do not touch `.git/`, `.env*`, or credential files.

{{efficiency_rules}}

