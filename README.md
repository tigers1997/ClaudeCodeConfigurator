# ClaudeCodeConfigurator

Headless CLI that generates Claude Code project scaffolding — `CLAUDE.md`, `.claude/settings.json`, hooks, subagents, skills, optionally `.mcp.json` — from an interactive intake form. Built for a single developer working in a git-enabled workflow on Debian, a dev server, or anywhere Python 3.8+ runs.

## Install

One-shot:

```bash
curl -sL https://raw.githubusercontent.com/tigers1997/ClaudeCodeConfigurator/main/install.sh | bash
```

Manual:

```bash
git clone https://github.com/tigers1997/ClaudeCodeConfigurator.git ~/.cc-configurator
ln -sf ~/.cc-configurator/configure.py ~/.local/bin/cc-configure
chmod +x ~/.cc-configurator/configure.py
# ensure ~/.local/bin is on $PATH
```

## Use

From any project directory:

```bash
cc-configure                             # interactive
cc-configure --yes --preset balanced     # one-shot with defaults
cc-configure --yes --preset aggressive \
  --modules core,safety,git-workflow,token-efficiency-pro,commands-core,agents
cc-configure --dry-run                   # preview what would be written
cc-configure --help                      # full flags
```

Answers persist to `.claude-config.json` in the project; re-runs with `--yes` reuse them. Existing files get backed up to `<name>.bak-<timestamp>` before overwrite.

## Modules

| Module | What it installs |
| --- | --- |
| **core** (required) | `CLAUDE.md` populated from your form answers, `.claude/settings.json`, `.gitignore` additions |
| **safety** | PreToolUse hooks: block dangerous bash, scan Write/Edit for secrets |
| **git-workflow** | PostToolUse formatter, Stop hook running typecheck / lint / tests |
| **token-efficiency** | Path-scoped `.claude/rules/` + PreCompact snapshot hook |
| **token-efficiency-pro** | Bash-output truncation hook + always-loaded discipline rules |
| **commands-core** | `/plan`, `/review`, `/commit`, `/ship`, `/sync-docs` |
| **agents** | `code-reviewer`, `test-runner`, `doc-writer`, `security-auditor` |
| **mcp** | `.mcp.json` generated from your selected servers |
| **ui** | Custom status line + "plan" output style |

## Token efficiency presets

- **Balanced** (recommended): discipline rules on, bash cap 80 lines, sonnet default.
- **Aggressive**: strict caps (40 lines), haiku-first subagents, `effort: minimal` on simple skills.
- **Relaxed**: most rules off — correctness over cost.

Individual toggles can be overridden after picking a preset.

## Flags

```
--dir DIR               Target project directory (default: .)
--config FILE           Load answers from a JSON file; skip prompts
--preset PRESET         balanced | aggressive | relaxed
--modules M1,M2,...     Comma-separated module IDs
--yes                   Accept defaults / saved config
--dry-run               Preview without writing
--no-backup             Don't back up overwritten files
--save-config FILE      Save answers to FILE (plus scaffolding)
--save-config-only FILE Save answers only, no scaffolding
```

## Repo layout

```
configure.py        # the CLI
config_schema.py    # modules + form fields
install.sh          # installer
templates/          # raw source for every file the CLI writes
docs/               # 7-part knowledge base
```

## Customizing templates

Everything the CLI writes lives under `templates/`. Edit freely, re-run `cc-configure` in a project, and the changes flow through.

To add a new module: create `templates/my-module/...`, add an entry to `MODULES` in `config_schema.py`, add a path rule to `target_path_for()` if needed. No rebuild step required.

Path-convention note: template files destined for `.claude/` in the target are stored under `templates/*/dot-claude/` here (workaround for environments that block dotfolder creation). The CLI rewrites `dot-claude/` → `.claude/` at install time. Same for `templates/mcp/mcp.json` → `.mcp.json`.

## License

MIT
