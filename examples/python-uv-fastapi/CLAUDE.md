# fastapi-demo

Example project scaffolded by cc-configure for a Python 3.12 + FastAPI stack using uv.

<!--
CLAUDE.md — project memory loaded at every session start.
Target: under 200 lines. Keep WHY/WHAT/HOW tight. Prefer file:line pointers
over pasted code. Put path-scoped detail in .claude/rules/*.md instead.
-->

**Repo:** git@github.com:example/fastapi-demo.git
**Default branch:** `main`
**License:** MIT

## WHY — what this project exists to do

- Ship the core feature reliably.
- Keep the codebase small and readable.
- Green CI on every push.

### Non-goals
- No multi-tenancy.
- No heavy framework abstraction.
- No custom UI framework.

## WHAT — the shape of the system

- **Language / runtime:** Python 3.12
- **Framework:** FastAPI
- **Package manager:** uv
- **Test runner:** pytest
- **Formatter:** ruff format
- **Typechecker:** mypy
- **Build tool:** uv build
- **Data:** Postgres (via SQLAlchemy)
- **Deployment target:** Fly.io

## HOW — the conventions that matter

### Commands
- Install: `uv sync`
- Dev: `uv run python -m app`
- Test: `uv run pytest`
- Lint: `uv run ruff check`
- Typecheck: `uv run mypy .`
- Build: `uv build`

### Code style
- **Indent:** 2 spaces
- **Max line length:** 100
- **Quote style:** single
- **Naming:** camelCase for vars/funcs, PascalCase for types/classes, SCREAMING_SNAKE for constants
- File size soft-cap: 300 lines. Split when crossed.
- Lint errors are build failures. Do not disable rules without a linked issue.
- Prefer pure functions + explicit types. Avoid global mutable state.

### Testing
- **Philosophy:** Tests alongside the code they cover
- Every new feature ships with tests. Integration tests for endpoints and flows.
- Run the test suite before committing.

### Git workflow
- **Commit style:** Conventional Commits
- **Branch strategy:** Trunk-based (short feature branches merged fast)
- One logical change per commit. Never commit directly to `main`.
- Before commit: format → lint → typecheck → test. All green.
- Use `git worktree add ../<name> -b feat/<name>` for parallel experiments.

## Design features

- **Architecture:** Layered: routes -> services -> repositories.
- **State management:** N/A (API only).
- **API style:** REST
- **Auth:** OAuth2 bearer tokens via fastapi.security.
- **Observability:** Structured JSON logs; OpenTelemetry traces; Sentry for errors.

## Common instructions (always apply)

- Prefer pydantic v2 models for request/response schemas.
- Async endpoints by default; sync only where blocking is intentional.
- Never handroll SQL; always go through SQLAlchemy.
- New dependencies require a brief justification in the commit message.

## Known gotchas

- The /auth/refresh endpoint must remain idempotent -- downstream clients retry on 5xx.
- Avoid importing from app.__init__; use app.main instead.
- Run migrations before tests on a fresh clone.

## External tools Claude may use

- **CLIs available:** git, gh, docker, kubectl, pnpm, psql
- **MCP servers enabled:** (none)

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

## Token efficiency rules

- **Scoped reads.** Read only the slice you need. Use `Read` with `offset` + `limit` for large files.
- **Grep over cat.** Prefer `grep` / `rg` for anything over 50 lines.
- **Narrow bash.** `git diff --stat` before `git diff`; `git log -5` before `git log`; `head`/`tail` when peeking.
- **Reset rhythm.** Task boundary: `/compact "focus hint"`. Task shift: `/clear`. Past 40% context: start fresh with a pasted summary.
- **Plan mode is cheap.** Read-only, no tool-output accumulation. First 2-3 turns of any non-trivial task.
- **Haiku-first for reads.** Read-only subagents default to haiku. Sonnet for writes; opus only for high-stakes review.
- **Description budget.** Keep skill + subagent descriptions under ~500 words total — they load every turn.
- **Bash output cap.** Long output truncated past 80 lines; full log goes to `.claude/logs/`. `tail` it if you need the rest.

