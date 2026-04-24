# Example: Python 3.12 + FastAPI (uv)

What you're looking at: the exact output of running `cc-configure` against a Python + FastAPI project using the `uv` package manager. All files in this directory are scaffolded — none were hand-edited after generation.

## Form inputs used

Captured in `.claude-config.json` in this same directory. Highlights:

| Field | Value |
|---|---|
| `project_name` | `fastapi-demo` |
| `stack_preset` | `Python (uv)` |
| `language` | `Python 3.12` |
| `framework` | `FastAPI` |
| `package_manager` | `uv` |
| `test_runner` | `pytest` |
| `formatter` | `ruff format` |
| `typechecker` | `mypy` |
| `cmd_test` | `uv run pytest` |
| `cmd_lint` | `uv run ruff check` |
| Modules enabled | `agents, commands-core, core, git-workflow, safety, token-efficiency, token-efficiency-pro` |
| MCP servers | `context7` only (library-docs lookup) |

The stack preset automatically filled the package manager / test runner / formatter / typechecker / build tool / command-cheatsheet fields with the Python-uv idioms. No manual entry per field.

## Tour of the key files

- **[`CLAUDE.md`](CLAUDE.md)** — project memory. Note the `Commands` section is pre-filled with `uv sync` / `uv run pytest` / etc. rather than the default `pnpm` versions. Also contains the "Working with Claude" collaboration section (task classification, slot-machine style, commit-as-you-go, spec-driven restart).
- **[`.claude/settings.json`](.claude/settings.json)** — permissions (`allow` / `ask` / `deny`) skewed toward Python tooling: `pytest`, `ruff`, no `pnpm`/`tsc`. Hooks wired for PreToolUse (block-dangerous-bash, scan-secrets), PostToolUse (format-on-write), Stop (stop-run-checks), PostToolUse on Bash (truncate-bash-output). `permissions.disableBypassPermissionsMode: "disable"` ships via the safety module.
- **[`.claude/rules/`](.claude/rules/)** — path-scoped rules (`frontend.md`, `backend.md`, `tests.md`) auto-load only when Claude is working with files matching their `paths:` glob. Only ~200 tokens load on a typical session instead of the whole ruleset.
- **[`.claude/skills/`](.claude/skills/)** — eight workflow skills: `/plan`, `/review`, `/commit`, `/ship`, `/sync-docs`, `/check-context`, `/session-retro`, `/verify-setup`.
- **[`.claude/agents/`](.claude/agents/)** — four specialists. `security-auditor.md` has Sonatype's dependency-management MCP wired via agent frontmatter — scoped to that agent only, so zero context cost when idle. Requires `SONATYPE_TOKEN` env var to activate.
- **[`.claude/hooks/`](.claude/hooks/)** — six shell scripts, all `.sh` native (no heavy-interpreter overhead). `scan-secrets.sh` and `block-dangerous-bash.sh` are the main PreToolUse guards; `stop-run-checks.sh` runs typecheck + lint + tests at the end of each turn.
- **[`.gitignore`](.gitignore)** — Claude-Code-related local-only paths added by `core/.gitignore.append`.

## What's *not* here vs. the full module catalog

This example uses the default module set. Not included here, but available as opt-ins via `--modules`:
- `mcp` — per-task MCP profiles + `./claude-ctx` wrapper
- `multi-agent` — guardrails + `/merge-worktrees` + `/infinite` + `parallel-generator` subagent
- `github-actions` — `.github/workflows/claude.yml` wired to `anthropics/claude-code-action@v1`
- `lockdown` — `DISABLE_UPDATES=1` for air-gapped setups
- `experiments-memory` — lazy-loaded `memory/experiments/`
- `ui` — custom status line + "plan" output style

If you want to see any of those opt-in modules in context, open an issue or add a second example (`examples/<slug-with-opt-in>/`) per the guide in [`../README.md`](../README.md).

## Regenerate this example

If the templates change in the parent repo, regenerate this example in place:

```bash
python3 configure.py \
    --config examples/python-uv-fastapi/.claude-config.json \
    --dir   examples/python-uv-fastapi
```

Commit any diff — that's the signal that templates moved and the example needed updating.
