# ClaudeCodeConfigurator

A comprehensive intake-form + module-picker that generates drop-in Claude Code project scaffolding. Designed for a single developer working in a git-enabled workflow.

## Quick start

Open `configurator.html` in your browser. It runs entirely client-side — no server, no build step.

1. **Fill in the intake form.** Project identity, goals/non-goals, tech stack, style conventions, design features, common instructions, external tools, token efficiency profile. Every field has a sensible default; skip what you don't care about.
2. **Pick modules.** Core is required. Add safety, git-workflow, token-efficiency, commands, agents, MCP, UI — or a subset.
3. **Download `setup.sh` (macOS / Linux / WSL) or `setup.ps1` (Windows).**
4. **Run it at the root of a new or existing project.** It writes `CLAUDE.md` (fully populated from your form), `.claude/settings.json`, `.claude/hooks/`, `.claude/agents/`, `.claude/skills/`, optionally `.mcp.json`, and appends a `.gitignore` block. Existing files get backed up with a timestamp.

## What's in the box

- **`configurator.html`** — the deliverable. Self-contained, ~119 KB, no external dependencies.
- **`templates/`** — the raw source for every file the configurator bakes in. Edit these and rerun the build script to regenerate.
- **`docs/`** — seven-part knowledge base covering project setup, git workflow, slash commands & hooks, subagents & MCP, safety & permissions, and token efficiency.
- **`build/build_configurator.py`** — the build script. Walks `templates/`, base64-encodes each file, and produces `configurator.html` from `build/configurator_template.html`.

## Modules

| Module | Description |
| --- | --- |
| **core** (required) | `CLAUDE.md` (placeholder-substituted from the form), `.claude/settings.json` with balanced permissions, `.gitignore` additions. |
| **safety** | PreToolUse hooks: block dangerous bash (`rm -rf`, `sudo`, `curl \| sh`, force push, hard reset) and scan Write/Edit for secrets. |
| **git-workflow** | PostToolUse formatter (prettier / ruff / gofmt / rustfmt), Stop hook that runs typecheck + lint + tests each turn. |
| **token-efficiency** | Path-scoped `.claude/rules/` starters + PreCompact snapshot hook. |
| **token-efficiency-pro** | PostToolUse bash-output truncation (cap via `CLAUDE_BASH_MAX_LINES`) + always-loaded discipline rules (scoped reads, grep-over-cat, inline-bash narrowing, `/compact` vs `/clear` vs fresh-session rhythm). The biggest lever from the book's token-efficiency chapter. |
| **commands-core** | `/plan`, `/review`, `/commit`, `/ship`, `/sync-docs` workflow skills. |
| **agents** | `code-reviewer`, `test-runner`, `doc-writer`, `security-auditor` subagents with sensible model assignments. |
| **mcp** | `.mcp.json` generated from your server selection (filesystem, git, github, playwright, context7). |
| **ui** | Custom status line + "plan" output style. |

## Token efficiency profile

The efficiency section of the form has three presets:

- **Balanced** (recommended): all discipline rules on, bash cap 80 lines, sonnet default.
- **Aggressive**: stricter caps (40 lines), haiku-first subagents, `effort: minimal` on simple skills.
- **Relaxed**: most rules off — correctness over cost.

You can override individual toggles after selecting a preset.

## Regenerating the configurator

```bash
cd build
python3 build_configurator.py
```

The build script expects:
- `templates/` (project root)
- `build/configurator_template.html` (the HTML shell)

It writes `configurator.html` at the project root.

## Notes on the workaround conventions

- Template files intended for `.claude/` live under `dot-claude/` in source because the original dev environment (OneDrive) blocked creating dotfolders directly. The build script rewrites `dot-claude/` → `.claude/` at encode time.
- Similarly `mcp/mcp.json` → `.mcp.json` at project root.

## License

MIT
