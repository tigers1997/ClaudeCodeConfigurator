# ClaudeCodeConfigurator

[![check](https://github.com/tigers1997/ClaudeCodeConfigurator/actions/workflows/check.yml/badge.svg)](https://github.com/tigers1997/ClaudeCodeConfigurator/actions/workflows/check.yml)

Headless CLI that generates Claude Code project scaffolding — `CLAUDE.md`, `.claude/settings.json`, hooks, subagents, skills, per-task MCP profiles, optional GitHub Action — from an interactive intake form. Built for a single developer working in a git-enabled workflow on Linux, macOS, or WSL.

## Requirements

**For running `cc-configure`:**
- **Python 3.8+** — stdlib only, no pip dependencies
- **git** — used by the installer and (later) by generated hooks / statusline
- **bash** — the shipped hook scripts and `./claude-ctx` wrapper all use `#!/usr/bin/env bash`
- **curl** — only for the one-shot install command
- **Claude Code 2.1.116–2.1.119** — the range the current templates are tested against (see `CLAUDE_CODE_COMPAT` in `config_schema.py`). The configurator runs a preflight check and prints a `[ VERSION WARNINGS ]` block if the installed `claude` is outside this range. Older CC silently drops features (agent-frontmatter `mcpServers: http`; `DISABLE_UPDATES`; `permissions.disableBypassPermissionsMode`). Each release states its compat range in `CHANGELOG.md`.

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

Answers persist to `.claude-config.json` in the project; re-runs with `--yes` reuse them.

**Retrofit safety (Tier 2, since v1.2.0).** When you run `cc-configure` against a project that already has Claude Code state, the default behavior is **non-destructive**:

- **Structured assets** (`.claude/settings.json`, `.mcp.json`) are **deep-merged**. Your customizations win on collisions; the configurator's additions layer on top. Output: a `[ MERGED ]` block summarizes per-file what was preserved vs added.
- **`CLAUDE.md`** follows `--claude-md` (default `append`):
  - `append` — merge our value-add sections (`## Working with Claude`, `## Claude Code behavior rules`, `## Token efficiency rules`) into your existing CLAUDE.md, preserving everything else verbatim. Idempotent on re-runs (won't double-append).
  - `skip` — your version untouched; ours staged at `.claude-retrofit/incoming/CLAUDE.md`.
  - `overwrite` — your version replaced, original backed up to `*.bak-<ts>`.
- **Other file-based assets** (skills, agents, rules, hooks) follow `--on-collision` (default `skip`):
  - `skip` — your version stays untouched; ours is staged at `.claude-retrofit/incoming/<original-path>` for manual review.
  - `rename` — both coexist: your `review/` stays put, ours installs as `review-cc/`.
  - `overwrite` — your file is replaced, original backed up to `*.bak-<ts>`.
- A `[ COLLISIONS ]` block lists what happened, and `.claude-retrofit/REPORT.md` records the full set with diff coordinates so you can resolve manually (or wait for the upcoming `/retrofit` skill, Tier 3).
- `--force` is a kill-switch: skip the merge AND the collision strategy entirely; just overwrite every existing file with `.bak-<ts>` backups (the pre-Tier-2 behavior).
- `--dry-run` shows the full would-be-written list (`+` for net-new, `~` for merged) without writing anything.


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

Before scaffolding, `cc-configure` runs four non-blocking checks and prints a warning block for each that fires, plus one **blocking** retrofit check:

- **`[ VERSION WARNINGS ]`** — compares `claude --version` against the declared `CLAUDE_CODE_COMPAT` range. Warns below min, informs above tested-up-to.
- **`[ SCHEMA WARNINGS ]`** — verifies the generated `settings.json`'s `$schema` matches `https://json.schemastore.org/claude-code-settings.json`. Claude Code silently drops the entire settings file on schema drift, so this guards the exact regression class that originally motivated this project.
- **`[ HOOK WARNINGS ]`** — flags hooks on high-frequency events (`PreToolUse`/`PostToolUse`/`PostToolUseFailure`) whose entrypoint is a heavy interpreter (`uv`, `python`, `node`, `poetry`, `npm`, `npx`, `pnpm`, `bun`, `deno`, `ruby`, `java`, `go`). Each call adds hundreds of ms.
- **`[ MODULE WARNINGS ]`** — currently: if the `github-actions` module is selected, verifies the target dir is a git repo with a GitHub remote; otherwise the Action will never trigger.
- **`[ MERGED ]` and `[ COLLISIONS ]` (informational)** — populated when running on an existing project. The configurator handles structured assets (`.claude/settings.json`, `.mcp.json`) via deep-merge and file-based assets (skills, agents, rules, hooks, CLAUDE.md) via the `--on-collision` strategy. See [Use](#use) above for the full retrofit-safety semantics. `.claude-retrofit/REPORT.md` records what happened.

All four non-blocking checks are silent on a clean default scaffold; the merge / collisions blocks are silent unless the target already contains files the configurator would write.

## Flags

```
--dir DIR               Target project directory (default: .)
--config FILE           Load answers from a JSON file; skip prompts
--preset PRESET         balanced | aggressive | relaxed
--modules M1,M2,...     Comma-separated module IDs
--yes                   Accept defaults / saved config
--dry-run               Preview without writing (informational only — bypasses
                        the retrofit-abort behavior)
--no-backup             Don't back up overwritten files (only relevant with --force)
--on-collision=MODE     How to handle file-based asset collisions (skills,
                        agents, rules, hooks). MODE is one of:
                          skip      (default) preserve yours; stage ours to
                                    .claude-retrofit/incoming/ for review.
                          rename    install ours alongside as <name>-cc; both
                                    coexist; nothing of yours is touched.
                          overwrite replace yours; original backs up to *.bak-<ts>.
                        Structured assets (.claude/settings.json, .mcp.json) are
                        always deep-merged regardless of this flag. CLAUDE.md
                        uses --claude-md.
--claude-md=MODE        How to handle CLAUDE.md collisions. MODE is one of:
                          append    (default) merge our value-add sections
                                    (## Working with Claude / ## Claude Code
                                    behavior rules / ## Token efficiency rules)
                                    into your existing CLAUDE.md, preserving
                                    everything else. Idempotent on re-runs.
                          skip      stage ours to .claude-retrofit/incoming/.
                          overwrite replace yours; original backs up.
--force                 Kill-switch: skip the deep-merge AND the collision
                        strategy. Every existing file is overwritten with .bak-<ts>
                        (the pre-Tier-2 behavior). Implies --on-collision=overwrite.
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

## Contributing

Issues and PRs welcome. **All changes to `main` go through a PR** — direct pushes are blocked by the repo's `MainBrnchRuleset`, which requires the `check` CI job green before merge. One-liners included; the gate is non-negotiable.

The flow:

1. **Branch from `main`.** Descriptive names: `feat/<thing>`, `fix/<thing>`, `docs/<thing>`, `chore/<thing>`.
2. **Push and open a PR against `main`.** `gh pr create --fill` is the fast path.
3. **CI (`check.yml`) must pass.** It runs `python3 configure.py --check` (static validation of templates + `MODULES` registry) plus a dry-run smoke test across every opt-in module.
4. **Describe the change briefly.** What it does, why, and any schema/template paths touched. Reference an issue number if one exists.
5. **Add a `CHANGELOG.md` entry** under `## Unreleased` using Keep-a-Changelog sections (`### Added`/`### Changed`/`### Fixed`/etc.). SHA-anchor after merge.
6. **Squash-merge by default.** One logical change per PR, one commit on `main`. `gh pr merge --squash --delete-branch` does it in one call.

Before opening a PR, local verification:

```bash
python3 configure.py --check    # same gate CI runs
```

Versioning: semver from v1.0.0 onward. Patch = bug fixes; minor = new modules/skills, backward-compatible; major = anything that invalidates a saved `.claude-config.json` or rewrites template paths.

## Acknowledgments

Portions of this project were informed by the MIT-licensed companion code in [PacktPublishing/Agentic-Coding-with-Claude-Code](https://github.com/PacktPublishing/Agentic-Coding-with-Claude-Code) (© 2026 Packt). In particular:

- `templates/ui/statusline-last-prompt.sh` adapts the transcript-reading pattern demonstrated in that repo's `Chapter08/statusline.py`.
- The multi-agent guardrails in `templates/multi-agent/dot-claude/rules/multi-agent-guardrails.md` reorganize and extend a taxonomy first presented by Eden Marco in *Agentic Coding with Claude Code* (Packt, 2026).

The configurator, its modules, the preflight-check architecture (`--check` / `check_schema_url` / `check_hook_weight` / `check_github_remote`), the stack-preset system, and all other scaffolding are original work.

## License

MIT
