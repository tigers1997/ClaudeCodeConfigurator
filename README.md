# ClaudeCodeConfigurator

[![check](https://github.com/tigers1997/ClaudeCodeConfigurator/actions/workflows/check.yml/badge.svg)](https://github.com/tigers1997/ClaudeCodeConfigurator/actions/workflows/check.yml)

Headless CLI that generates Claude Code project scaffolding — `CLAUDE.md`, `.claude/settings.json`, hooks, subagents, skills, per-task MCP profiles, optional GitHub Action — from an interactive intake form. Built for a single developer working in a git-enabled workflow on Linux, macOS, or WSL.

## Requirements

**For running `cc-configure`:**
- **Python 3.8+** — stdlib only, no pip dependencies
- **git** — used by the installer and (later) by generated hooks / statusline
- **bash** — the shipped hook scripts and `./claude-ctx` wrapper all use `#!/usr/bin/env bash`
- **curl** — only for the one-shot install command

**Generated projects need, depending on which modules you enable:**
- **`ui`** — `python3` + `git` (used by `statusline.sh` and the last-prompt variant)
- **`git-workflow`** — whichever formatters/checkers you've selected: typically `prettier`, `ruff`, `gofmt`, `rustfmt`, `tsc`, or `eslint`. The format-on-write hook auto-detects which to invoke based on file extension; missing tools fail silently for that file type.
- **`safety`** — standard POSIX tools (`grep`, `tr`, etc.)
- **`token-efficiency-pro`** — standard POSIX tools (`awk`, `tail`, `wc`)
- **`mcp`** — `npx` (Node) or `uvx` (Python) depending on which MCP servers you enable; `./claude-ctx` wrapper needs `bash` and the `claude` CLI on PATH

## Platform support

| Platform | Status |
| --- | --- |
| **Linux** (Debian/Ubuntu/Arch/Fedora/…) | Primary target. Everything works out of the box. |
| **macOS** (12+) | Works. Bash 3.2 from the system is sufficient; scripts use POSIX-safe flags. |
| **Windows** | **WSL recommended.** Native cmd/PowerShell cannot execute the `.sh` hooks this project ships. For Windows-native hooks you'd need to translate each script to PowerShell and set `"shell": "powershell"` on each hook entry (per the Claude Code docs). The template directory uses `dot-claude/` (rewritten to `.claude/` at install) specifically as a OneDrive-safe workaround — but Windows-native hook execution is not supported out of the box. |

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

## Stack presets

The Tech-stack section leads with a **stack preset** picker. Selecting one prefills downstream defaults — package manager, test runner, formatter, typechecker, build tool, and the entire Commands cheatsheet — *before* those fields are prompted.

| Preset | Stack |
| --- | --- |
| `Node + TypeScript (pnpm)` | TS 5 / Node 20 / Next.js 15 / pnpm / vitest / tsc / prettier |
| `Node + JavaScript (npm)` | JS / Node 20 / Express / npm / vitest / prettier |
| `Python (uv)` | Python 3.12 / FastAPI / uv / pytest / ruff / mypy |
| `Python (poetry)` | Python 3.12 / FastAPI / poetry / pytest / black / mypy |
| `Python (pip + venv)` | Python 3.12 / FastAPI / pip / pytest / black / mypy |
| `Go` | Go 1.22 / stdlib net/http / `go mod` / `go test` / gofmt / `go vet` |
| `Rust` | Rust 1.82 / axum / cargo / rustfmt / clippy |
| `Custom / keep current` | No-op — leave every downstream field as shown |

Picking `Python (uv)` flips `cmd_test` from `pnpm test` to `uv run pytest`, etc. Override individual fields after the preset if needed.

## Modules

| Module | What it installs |
| --- | --- |
| **core** (required) | `CLAUDE.md` populated from your answers, `.claude/settings.json`, `.gitignore` additions. `CLAUDE.md` includes a "Working with Claude" collaboration section (task classification / slot-machine / commit-as-you-go / self-sufficient loops / spec-driven restart). |
| **safety** | PreToolUse hooks (block dangerous bash + scan Write/Edit for secrets) and `permissions.disableBypassPermissionsMode: "disable"` — hard-blocks `--dangerously-skip-permissions`. |
| **git-workflow** | PostToolUse formatter on Write/Edit, Stop hook running typecheck / lint / tests. |
| **token-efficiency** | Path-scoped `.claude/rules/` starters + PreCompact snapshot hook. |
| **token-efficiency-pro** | Bash-output truncation hook + always-loaded discipline rules. |
| **commands-core** | Eight workflow skills: `/plan`, `/review`, `/commit`, `/ship`, `/sync-docs`, `/check-context`, `/session-retro`, `/verify-setup`. Auto-pulls **agents** via module dependency. |
| **agents** | Four subagents: `code-reviewer`, `test-runner`, `doc-writer`, `security-auditor`. The `security-auditor` frontmatter wires Sonatype's dependency-management MCP (`https://mcp.guide.sonatype.com/mcp`) scoped to that agent — active only when it runs, so ~0 baseline context cost. Set `SONATYPE_TOKEN` env var to enable ([generate a token](https://guide.sonatype.com/settings/tokens)). |
| **mcp** | `.mcp.json` generated from selected servers, plus **per-task profiles** (`.mcp.research.json`, `.mcp.frontend.json`, `.mcp.minimal.json`) and an executable `./claude-ctx` wrapper that launches Claude with `--mcp-config <profile> --strict-mcp-config` — drops a bloated 4-MCP baseline from ~49% context to under 5%. |
| **multi-agent** | Path-scoped `multi-agent-guardrails.md` (5-scenario "when not to parallel" list), `/merge-worktrees` skill, `/infinite` skill, `parallel-generator` subagent. |
| **github-actions** | `.github/workflows/claude.yml` pinned to `anthropics/claude-code-action@v1`. Triggers on `@claude` mentions in issues, PR comments, and PR reviews. |
| **ui** | Custom status line (project \| branch \| model \| ctx%; optionally effort + thinking indicators when 2.1.119+ is running), `statusline-last-prompt.sh` variant, and a "plan" output style. |
| **lockdown** | Opt-in only. Sets `DISABLE_UPDATES=1` in settings env — blocks autoupdates AND manual `claude update`. For air-gapped / enterprise environments. |
| **experiments-memory** | Opt-in only. Lazy-loaded `memory/experiments/CLAUDE.md` defines a 5-section format (hypothesis/setup/result/conclusion/follow-ups) for logging experiments. Zero context cost until Claude reads files in that folder. |

## Token-efficiency presets

- **Balanced** (recommended): discipline rules on, bash cap 80 lines, sonnet default.
- **Aggressive**: strict caps (40 lines), haiku-first subagents, `effort: minimal` stamped directly into `/check-context`, `/sync-docs`, `/session-retro` frontmatter.
- **Relaxed**: most rules off — correctness over cost.

Individual toggles can be overridden after picking a preset.

## Preflight checks

Before scaffolding, `cc-configure` runs three non-blocking checks and prints warnings for each that fires:

- **`[ SCHEMA WARNINGS ]`** — verifies the generated `settings.json`'s `$schema` matches `https://json.schemastore.org/claude-code-settings.json`. Claude Code silently drops the entire settings file on schema drift, so this guards the exact regression class that originally motivated this project.
- **`[ HOOK WARNINGS ]`** — flags hooks on high-frequency events (`PreToolUse`/`PostToolUse`/`PostToolUseFailure`) whose entrypoint is a heavy interpreter (`uv`, `python`, `node`, `poetry`, `npm`, `npx`, `pnpm`, `bun`, `deno`, `ruby`, `java`, `go`). Each call adds hundreds of ms.
- **`[ MODULE WARNINGS ]`** — currently: if the `github-actions` module is selected, verifies the target dir is a git repo with a GitHub remote; otherwise the Action will never trigger.

All three are silent on a clean default scaffold.

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
--check                 Static validation of templates + MODULES (CI gate);
                        exits 0 on clean, 1 on any failure
```

## Repo layout

```
configure.py        # the CLI
config_schema.py    # modules + form fields + stack presets
install.sh          # installer
templates/          # raw source for every file the CLI writes
docs/               # 9-part knowledge base (overview → memory hierarchy)
```

## Customizing templates

Everything the CLI writes lives under `templates/`. Edit freely, re-run `cc-configure` in a project, and the changes flow through.

To add a new module: create `templates/my-module/…`, add an entry to `MODULES` in `config_schema.py`, add a path rule to `target_path_for()` if the routing isn't covered by the defaults. Declare `dependsOn: ["other-module"]` if your module references primitives shipped by another (e.g. `commands-core` depends on `agents`).

After editing, validate your changes:

```bash
python3 configure.py --check
```

The same check runs in CI on every push and PR (`.github/workflows/check.yml`). It walks `MODULES` + every template file and verifies: paths resolve, JSON parses, bash scripts pass `bash -n`, SKILL.md / agent frontmatter has `name:` and `description:`, `dependsOn:` references are valid.

**Path conventions** the CLI rewrites at install time:

- `templates/*/dot-claude/*` → `.claude/*` (workaround for environments that block dotfolder creation)
- `templates/*/dot-github/*` → `.github/*`
- `templates/mcp/mcp.json` → `.mcp.json`
- `templates/mcp/profiles/mcp.<name>.json` → `.mcp.<name>.json` at repo root
- `templates/mcp/servers-cookbook.md` → `docs/mcp-servers.md`

## Acknowledgments

Portions of this project were informed by the MIT-licensed companion code in [PacktPublishing/Agentic-Coding-with-Claude-Code](https://github.com/PacktPublishing/Agentic-Coding-with-Claude-Code) (© 2026 Packt). In particular:

- `templates/ui/statusline-last-prompt.sh` adapts the transcript-reading pattern demonstrated in that repo's `Chapter08/statusline.py`.
- The multi-agent guardrails in `templates/multi-agent/dot-claude/rules/multi-agent-guardrails.md` reorganize and extend a taxonomy first presented by Eden Marco in *Agentic Coding with Claude Code* (Packt, 2026).

The configurator, its modules, the preflight-check architecture (`--check` / `check_schema_url` / `check_hook_weight` / `check_github_remote`), the stack-preset system, and all other scaffolding are original work.

## License

MIT
