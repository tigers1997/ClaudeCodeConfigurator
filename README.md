# ClaudeCodeConfigurator

[![check](https://github.com/tigers1997/ClaudeCodeConfigurator/actions/workflows/check.yml/badge.svg)](https://github.com/tigers1997/ClaudeCodeConfigurator/actions/workflows/check.yml)

Headless CLI that generates Claude Code project scaffolding — `CLAUDE.md`, `.claude/settings.json`, hooks, subagents, skills, per-task MCP profiles, optional GitHub Action — from an interactive intake form. Built for a single developer working in a git-enabled workflow on Linux, macOS, or WSL.

## Requirements

**For running `cc-configure`:**
- **Python 3.8+** — stdlib only, no pip dependencies
- **git** — used by the installer and (later) by generated hooks / statusline
- **bash** — the shipped hook scripts and `./claude-ctx` wrapper all use `#!/usr/bin/env bash`
- **curl** — only for the one-shot install command
- **Claude Code 2.1.116–2.1.132** — the range the current templates are tested against (see `CLAUDE_CODE_COMPAT` in `config_schema.py`). The configurator runs a preflight check and prints a `[ VERSION WARNINGS ]` block if the installed `claude` is outside this range. Older CC silently drops features (agent-frontmatter `mcpServers: http`; `DISABLE_UPDATES`; `permissions.disableBypassPermissionsMode`). Each release states its compat range in `CHANGELOG.md`.

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
| **Windows** | Claude Code 2.1.120+ runs natively on Windows — when Git Bash is absent, Claude Code falls back to PowerShell as its shell tool. However, the `.sh` hook scripts this project ships still need a bash interpreter to execute. Three options: install Git Bash (via Git for Windows), use WSL, or translate each hook to PowerShell and set `"shell": "powershell"` on the hook entry (per the Claude Code docs). The template directory uses `dot-claude/` (rewritten to `.claude/` at install) so the templates browse and sync cleanly on filesystems and tools that special-case dotfiles. |

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

> First time? See [`docs/11-getting-started.md`](docs/11-getting-started.md) for the two end-to-end walkthroughs (brand-new project with `superpowers` brainstorming first, or existing-project retrofit with `/retrofit`).

From any project directory:

```bash
cc-configure                               # quick mode (5 questions)
cc-configure --detailed                    # full 55-field intake (v1 behavior)
cc-configure --persona solo-newer --yes    # one-shot for newer coders
cc-configure --persona small-team --yes    # one-shot, team kit
cc-configure --yes                         # reuse existing .claude-config.json
cc-configure --dry-run                     # preview without writing
cc-configure --help                        # full flags
```

Quick mode asks **five questions**: persona, project name, stack preset, repo URL, license. The persona pre-picks modules + flags + sensible defaults; documentation fields default to bracketed `[TODO: ...]` placeholders the user fills in later.

### Personas

| Persona | Pre-picks |
|---|---|
| `solo-newer` | `core / safety / git-workflow / token-efficiency (basic) / commands (curated) / mcp (context7)`; documentation fields default to `[TODO:]` placeholders; "Solo on main, squash-merge" branch strategy |
| `solo-experienced` | + `token-efficiency (pro) / commands (rigorous) / ui` (today's de-facto default; `rigorous` adds `/investigate` + `/plan-eng-review` on top of the `full` skill set) |
| `small-team` | `solo-experienced` + `multi-agent / github-actions`; trunk-based default |
| `library-author` | `core / safety / git-workflow / commands (full) / github-actions`; MIT default |
| `custom` | nothing pre-picked; lands in `--detailed` |

All non-`custom` personas pre-set `safety.slop_scan = true` (warn-mode PostToolUse hook flagging filler / marketing / hedging / em-dash patterns).

Answers persist to `.claude-config.json` in the project; re-runs with `--yes` reuse them. Existing v1 `.claude-config.json` files (no `persona` field) load unchanged and behave as `persona: custom`.

### Legacy flag compatibility

`--preset balanced|aggressive|relaxed` and the legacy module names (`commands-core`, `agents`, `lockdown`, `token-efficiency-pro`) continue to work. Each emits a line in a new `[ DEPRECATED ]` block showing the v3.0 migration. Slated for removal in v3.0.

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
- A `[ COLLISIONS ]` block lists what happened, and `.claude-retrofit/REPORT.md` records the full set with diff coordinates.
- `--force` is a kill-switch: skip the merge AND the collision strategy entirely; just overwrite every existing file with `.bak-<ts>` backups (the pre-Tier-2 behavior).
- `--dry-run` shows the full would-be-written list (`+` for net-new, `~` for merged) without writing anything.

**Resolving staged conflicts.** Two paths after a retrofit run:

- **Manual** — diff each pair from `.claude-retrofit/REPORT.md` and decide per file. Section examples + the bigger triage discipline ("what belongs in CLAUDE.md vs. elsewhere") are in [`docs/09-retrofit-guide.md`](docs/09-retrofit-guide.md).
- **Guided** — run `/retrofit` in a Claude Code session. The skill walks the report one entry at a time, shows the diff, offers five choices per entry (Keep / Replace / Merge / Rename / Skip), and applies your decision with backups. Ships in `commands-core` so it's available right after the scaffold completes.


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

There are 11 modules; legacy IDs (`commands-core`, `agents`, `token-efficiency-pro`, `lockdown`) still translate to their post-v1.6.0 homes.

| Module | What it installs |
| --- | --- |
| **core** (required) | `CLAUDE.md` populated from your answers, `.claude/settings.json`, `.gitignore` additions. `CLAUDE.md` includes a "Working with Claude" collaboration section (task classification / slot-machine / commit-as-you-go / self-sufficient loops / spec-driven restart). |
| **safety** | PreToolUse hooks (block dangerous bash + scan Write/Edit for secrets); `permissions.disableBypassPermissionsMode: "disable"` hard-blocks `--dangerously-skip-permissions`. Sub-flags: `lockdown` (sets `DISABLE_UPDATES=1` — blocks autoupdates AND manual `claude update`; for air-gapped / enterprise environments); `slop_scan` (PostToolUse hook on Write/Edit/NotebookEdit flagging filler / marketing-voice / hedging / em-dash patterns; `slop_scan_action=warn\|block`, `slop_scan_density` and `slop_scan_imports` opt-in). All non-`custom` personas pre-set `slop_scan=true` action=warn. |
| **git-workflow** | PostToolUse formatter on Write/Edit, Stop hook running typecheck / lint / tests. |
| **token-efficiency** | Path-scoped `.claude/rules/` starters + PreCompact snapshot hook. `tier` flag: `basic` (default) ships discipline rules + snapshot only; `pro` adds bash-output truncation hook + always-loaded discipline rules. |
| **commands** | Slash commands + agents + microbits. `subset` flag (linear ordering: `curated ⊂ full ⊂ rigorous`): **`curated`** = 3 essential skills (`/plan`, `/commit`, `/verify-setup`) + the `code-reviewer` agent. **`full`** (default) = 9 workflow skills (adds `/review`, `/ship`, `/sync-docs`, `/check-context`, `/session-retro`, `/retrofit`) + 4 agents (`code-reviewer`, `test-runner`, `doc-writer`, `security-auditor`) + 4 discipline microbits (`/freeze`, `/unfreeze`, `/guard`, `/careful`) + the `microbit-enforcer.sh` PreToolUse hook. **`rigorous`** = `full` + `/investigate` + `/plan-eng-review`, the rigor skills that embed `templates/commands/_patterns/` cross-cutting blocks (confidence gate, independent verification, no-fix-without-investigation, AI-slop detection). The `security-auditor` frontmatter wires Sonatype's dependency-management MCP (`https://mcp.guide.sonatype.com/mcp`) scoped to that agent — active only when it runs, so ~0 baseline context cost. Set `SONATYPE_TOKEN` env var to enable ([generate a token](https://guide.sonatype.com/settings/tokens)). |
| **mcp** | `.mcp.json` generated from selected servers, plus **per-task profiles** (`.mcp.research.json`, `.mcp.frontend.json`, `.mcp.minimal.json`) and an executable `./claude-ctx` wrapper that launches Claude with `--mcp-config <profile> --strict-mcp-config` — drops a bloated 4-MCP baseline from ~49% context to under 5%. |
| **multi-agent** | Path-scoped `multi-agent-guardrails.md` (5-scenario "when not to parallel" list), `/merge-worktrees` skill, `/infinite` skill, `parallel-generator` subagent. |
| **github-actions** | `.github/workflows/claude.yml` pinned to `anthropics/claude-code-action@v1`. Triggers on `@claude` mentions in issues, PR comments, and PR reviews. |
| **ui** | Custom status line (project \| branch \| model \| ctx%; optionally effort + thinking indicators when 2.1.119+ is running), `statusline-last-prompt.sh` variant, and a "plan" output style. |
| **recommend-plugins** | Drops `docs/recommended-plugins.md` — a stack-aware list of official Claude Code plugins worth considering (always-recommended set + stack-specific picks computed from your form answers). Reference doc; refreshes on every `cc-configure` run. See [`docs/10-plugin-ecosystem.md`](docs/10-plugin-ecosystem.md) for how plugins relate to the configurator. |
| **experiments-memory** | Opt-in only. Lazy-loaded `memory/experiments/CLAUDE.md` defines a 5-section format (hypothesis/setup/result/conclusion/follow-ups) for logging experiments. Zero context cost until Claude reads files in that folder. |

## Token-efficiency presets

The legacy `--preset` flag (slated for removal in v3.0 — use `--persona` instead) maps to one of three bundles:

- **Balanced** (recommended): discipline rules on, bash cap 80 lines, sonnet default.
- **Aggressive**: strict caps (40 lines), haiku-first subagents, `effort: minimal` stamped directly into `/check-context`, `/verify-setup`, `/sync-docs`, `/session-retro` frontmatter.
- **Relaxed**: most rules off — correctness over cost.

Individual toggles can be overridden after picking a preset. Personas (the v2.x replacement) bundle these defaults together with module / form-value picks; see [Personas](#personas).

## Preflight checks

Before scaffolding, `cc-configure` runs five non-blocking checks and prints a warning block for each that fires:

- **`[ VERSION WARNINGS ]`** — compares `claude --version` against the declared `CLAUDE_CODE_COMPAT` range. Warns below min, informs above tested-up-to.
- **`[ SCHEMA WARNINGS ]`** — verifies the generated `settings.json`'s `$schema` matches `https://json.schemastore.org/claude-code-settings.json`. Claude Code silently drops the entire settings file on schema drift, so this guards the exact regression class that originally motivated this project.
- **`[ HOOK WARNINGS ]`** — flags hooks on high-frequency events (`PreToolUse`/`PostToolUse`/`PostToolUseFailure`) whose entrypoint is a heavy interpreter (`uv`, `python`, `node`, `poetry`, `npm`, `npx`, `pnpm`, `bun`, `deno`, `ruby`, `java`, `go`). Each call adds hundreds of ms.
- **`[ MODULE WARNINGS ]`** — currently: if the `github-actions` module is selected, verifies the target dir is a git repo with a GitHub remote; otherwise the Action will never trigger.
- **`[ ENV WARNINGS ]`** — when an MCP server (or an agent that scopes one) is enabled but its required env var isn't set, surfaces it before scaffolding so the silent-never-connected failure mode happens never. Currently checks `GITHUB_TOKEN` (if `mcp_github` is enabled) and `SONATYPE_TOKEN` (if `commands` is selected — `security-auditor` scopes the Sonatype MCP).

Additional informational blocks render when their condition fires: **`[ DESIGN DETECTED ]`** (target dir already has design output — Next-steps printer adapts), **`[ APPLIED ]`** (persona + final module list with active flag values), **`[ DEPRECATED ]`** (legacy `--preset` / `--modules` aliases used), **`[ NOTICE ]`** (one-time persona prompt for v1 configs), **`[ PLACEHOLDERS ]`** (lists every `[TODO:]` field), **`[ NEXT STEPS ]`** (tailored tips), and **`[ MERGED ]` / `[ COLLISIONS ]`** for retrofit runs (see [Use](#use) for retrofit-safety semantics; `.claude-retrofit/REPORT.md` records what happened).

All five preflight checks are silent on a clean default scaffold; informational blocks are silent unless their condition fires.

## Flags

```
--dir DIR               Target project directory (default: .)
--config FILE           Load answers from a JSON file; skip prompts
--detailed              Run the full 55-field interactive intake (v1 behavior).
                        Default is 5-question quick mode.
--persona NAME          Persona pre-pick: solo-newer | solo-experienced |
                        small-team | library-author | custom. Combine with
                        --yes for fully non-interactive scaffolding.
--preset PRESET         balanced | aggressive | relaxed (deprecated; slated
                        for removal in v3.0 — use --persona instead).
--modules M1,M2,...     Comma-separated module IDs. Legacy IDs (lockdown,
                        token-efficiency-pro, commands-core, agents) still
                        accepted; each emits a [ DEPRECATED ] line.
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
docs/               # 12-part knowledge base (00-overview → 11-getting-started;
                    #  07-backlog.md is gitignored as local-only roadmap)
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

Additional patterns were distilled from the MIT-licensed [garrytan/gstack](https://github.com/garrytan/gstack) (© 2026 Garry Tan). No gstack files are vendored; the configurator translates the patterns into its own voice. In particular:

- The cross-cutting prompt blocks under `templates/commands/_patterns/` (confidence gate, independent verification, no-fix-without-investigation, AI-slop detection) and the `/investigate` and `/plan-eng-review` rigor skills distill methodology demonstrated in gstack's rigor command set.
- The four discipline microbits (`/freeze`, `/unfreeze`, `/guard`, `/careful`) and their PreToolUse enforcer adapt the marker-file discipline pattern from gstack.
- The `security-auditor` agent's confidence gate (≥8), false-positive exclusion list, concrete-exploit requirement, and lightweight STRIDE checklist are distilled from gstack's `/cso` security-review skill.
- The `slop-scan` PostToolUse hook in `templates/safety/` adapts the AI-slop pattern catalog from gstack.

The `discipline-skills` module ships a curated 7-skill subset (brainstorming, writing-plans, executing-plans, verification-before-completion, using-git-worktrees, subagent-driven-development, finishing-a-development-branch) forked from the MIT-licensed [obra/superpowers](https://github.com/obra/superpowers) v5.1.0 plugin by Jesse Vincent (© 2025 Jesse Vincent). The skill bodies are lightly edited: bare cross-references replace `superpowers:`-prefixed ones, the visual-companion section is stripped from brainstorming, the `requesting-code-review` template is embedded inline into `subagent-driven-development/code-quality-reviewer-prompt.md`, and a slim SessionStart bootstrap replaces the upstream `using-superpowers` injection. See `templates/discipline-skills/LICENSE` for the upstream MIT notice and `templates/discipline-skills/SYNC.md` for the maintainer-internal sync workflow.

The configurator, its modules, the preflight-check architecture (`--check` / `check_schema_url` / `check_hook_weight` / `check_github_remote`), the stack-preset system, and all other scaffolding are original work.

## License

**GNU Affero General Public License v3.0** (AGPL-3.0) — see `LICENSE`.

The configurator switched from MIT to AGPL-3.0 to close the SaaS-loophole used to fork copyleft projects into closed managed services (the "MongoDB on AWS" pattern). Self-hosting and use in open-source projects remain free; closed-source or commercial managed-service use requires a separate license.

Carve-out: `templates/discipline-skills/` remains under the **MIT License** (© 2025 Jesse Vincent), forked from the MIT-licensed [obra/superpowers](https://github.com/obra/superpowers) v5.1.0 plugin. The MIT terms travel with those files when users install the module into their own projects. See `NOTICE` for the full bundled-license breakdown and `templates/discipline-skills/LICENSE` for the upstream MIT notice.

Past releases tagged before this commit remain available under the MIT license they shipped under; the AGPL-3.0 terms apply to all subsequent code.
