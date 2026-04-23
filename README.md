# ClaudeCodeConfigurator

A comprehensive intake-form + module-picker that generates drop-in Claude Code project scaffolding. Designed for a single developer working in a git-enabled workflow. Works both in a browser (`configurator.html`) and as a headless CLI (`configure.py`).

## Quick start — headless (Debian, server, CI)

One-shot install:

```bash
curl -sL https://raw.githubusercontent.com/tigers1997/ClaudeCodeConfigurator/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/tigers1997/ClaudeCodeConfigurator.git ~/.cc-configurator
ln -sf ~/.cc-configurator/configure.py ~/.local/bin/cc-configure
chmod +x ~/.cc-configurator/configure.py
# ensure ~/.local/bin is on PATH
```

Then, from any project:

```bash
cd your-project
cc-configure                                    # interactive TUI
cc-configure --yes --preset aggressive          # one-shot with defaults
cc-configure --dry-run                          # preview what would be written
cc-configure --help                             # full options
```

Your answers are saved to `.claude-config.json` in the project directory; re-running with `--yes` reuses them. Existing files get backed up to `<name>.bak-<timestamp>` before overwrite.

## Quick start — browser (desktop)

Open `configurator.html` in your browser. It runs entirely client-side — no server, no build step.

1. Fill in the intake form. Every field has a sensible default; skip what you don't care about.
2. Pick modules.
3. Download `setup.sh` (macOS / Linux / WSL) or `setup.ps1` (Windows).
4. Run it from the root of a target project.

## What's in the box

| Path | Purpose |
| --- | --- |
| `configure.py` | Headless CLI. Stdlib-only, Python 3.8+. |
| `configurator.html` | Browser UI. Self-contained, ~118 KB. |
| `config_schema.py` | Shared source-of-truth for modules + form fields. Edit here to change both UIs. |
| `templates/` | Raw source for every file the configurator bakes in. |
| `build/build_configurator.py` | Regenerates `configurator.html` from `templates/` + `config_schema.py`. |
| `build/configurator_template.html` | HTML shell the build script populates. |
| `docs/` | Seven-part knowledge base (project setup, git workflow, commands & hooks, subagents/MCP, safety, token efficiency, overview). |
| `install.sh` | One-shot installer. |

## Modules

| Module | Description |
| --- | --- |
| **core** (required) | `CLAUDE.md` (placeholder-substituted from the form), `.claude/settings.json` with balanced permissions, `.gitignore` additions. |
| **safety** | PreToolUse hooks: block dangerous bash (`rm -rf`, `sudo`, `curl \| sh`, force push, hard reset) and scan Write/Edit for secrets. |
| **git-workflow** | PostToolUse formatter (prettier / ruff / gofmt / rustfmt), Stop hook that runs typecheck + lint + tests each turn. |
| **token-efficiency** | Path-scoped `.claude/rules/` starters + PreCompact snapshot hook. |
| **token-efficiency-pro** | PostToolUse bash-output truncation (cap via `CLAUDE_BASH_MAX_LINES`) + always-loaded discipline rules (scoped reads, grep-over-cat, inline-bash narrowing, `/compact` vs `/clear` vs fresh-session rhythm). The biggest lever from the book's token-efficiency chapter. |
| **commands-core** | `/plan`, `/review`, `/commit`, `/ship`, `/sync-docs` workflow skills. |
| **agents** | `code-reviewer`, `test-runner`, `doc-writer`, `security-auditor` subagents. |
| **mcp** | `.mcp.json` generated from your server selection (filesystem, git, github, playwright, context7). |
| **ui** | Custom status line + "plan" output style. |

## Token efficiency profile

Three presets flip all the discipline rules at once:

- **Balanced** (recommended): all discipline rules on, bash cap 80 lines, sonnet default.
- **Aggressive**: stricter caps (40 lines), haiku-first subagents, `effort: minimal` on simple skills.
- **Relaxed**: most rules off — correctness over cost.

Override individual toggles after selecting a preset.

## CLI reference

```
usage: configure.py [--dir DIR] [--config FILE] [--save-config FILE]
                    [--save-config-only FILE] [--preset {balanced,aggressive,relaxed}]
                    [--modules M1,M2,...] [--yes] [--dry-run] [--no-backup]

--dir DIR               Target project directory (default: .)
--config FILE           Load config from JSON; skip prompts
--preset PRESET         Non-interactive: apply efficiency preset
--modules M1,M2,...     Non-interactive: comma-separated module IDs
--yes                   Accept all defaults (combine with --preset / --modules)
--dry-run               Show what would be written and exit
--no-backup             Don't back up existing files
--save-config FILE      Save resulting config to FILE (plus scaffolding)
--save-config-only FILE Save config only, no scaffolding
```

Example: scaffold a Python project non-interactively.

```bash
cc-configure --dir ~/work/my-api --yes \
  --preset aggressive \
  --modules core,safety,git-workflow,token-efficiency-pro,commands-core,agents
```

## Regenerating the browser HTML

```bash
python3 build/build_configurator.py
```

The build script imports from `config_schema.py`, so edits to fields or modules there flow into both the CLI and the HTML on the next rebuild.

## Path-convention note

Template files intended for `.claude/` in the target are stored under `templates/*/dot-claude/` here because the original dev environment (OneDrive) blocked creating dotfolders directly. The configurator (both CLI and HTML) rewrites `dot-claude/` → `.claude/` at install time. Same for `templates/mcp/mcp.json` → `.mcp.json`.

## License

MIT
