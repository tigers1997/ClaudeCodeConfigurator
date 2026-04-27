# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Semantic Versioning from v1.0.0 onward; each entry references its commit SHA.

## Unreleased

### Added
- **Retrofit safety — Tier 2 (PR 2a): deep-merge `.claude/settings.json` and `.mcp.json`.** When the configurator detects an existing copy of either file, it now merges the user's customizations with the configurator's planned content instead of forcing a `--force`-or-abort decision. Strategy: user's values win on collisions (preserves their explicit choices); canonical `$schema` and security-default `permissions.disableBypassPermissionsMode` get ours; `permissions.allow`/`.ask`/`.deny`/`additionalDirectories` are unioned (existing first, new entries appended without duplicates); hooks are concatenated per-event (no dedupe — manually remove any unintended duplicates); `env` keys preserve existing values on collision; `statusLine`/`model` preserve existing if set; unknown top-level keys pass through verbatim. After scaffold, a new `[ MERGED ]` block summarizes what was preserved vs added per file. Backup behavior unchanged: the original file gets a `.bak-<ts>` before the merged version is written. Tier 1 abort still fires for any non-structured collision (skill/agent/rule/hook/CLAUDE.md). Suppressed when aborting (we said "merged" only if we actually write).
- New helpers: `_merge_unique_list`, `deep_merge_settings`, `deep_merge_mcp`, `apply_structured_merges` in `configure.py`.
- Dry-run output now distinguishes merged files with `~` vs net-new files with `+`.

### Changed
- **Stop hook now uses your form-configured commands, not hardcoded JS tooling.** `templates/git-workflow/hooks/stop-run-checks.sh` previously had `npx --no-install tsc`/`eslint`/`vitest` hardcoded, which silently broke for any non-JS project — `command -v npx` succeeds on most dev machines, but the actual tools aren't there, so every Stop fired a FAIL report on every turn. Real-use feedback from a Python+FastAPI project surfaced the gap; the maintainer disabled the entire `git-workflow` module to avoid the noise. The hook now substitutes `{{cmd_typecheck}}` / `{{cmd_lint}}` / `{{cmd_test}}` from the intake form, so a `Python (uv)` preset produces `uv run mypy .` / `uv run ruff check` / `uv run pytest`. Empty-after-substitution commands are skipped silently — blanking a field in the form is now the way to say "I don't have a typecheck/lint/test setup." The existing runtime `command -v <first-token>` defense-in-depth check is preserved.

### Added
- **Retrofit safety — Tier 1.** New `check_retrofit_state()` helper detects existing files at the target that would be overwritten. `cc-configure` now refuses to clobber by default — emits a `[ RETROFIT WARNINGS ]` block listing every collision, prints the three resolution paths (`--force` / `--dry-run` / move-files-manually), and exits with status `2`. Real-use trigger: running v1.1 on an existing complex project (370-line CLAUDE.md + custom hooks + custom skills) silently overwrote everything except for per-file `.bak-<ts>` fallbacks the user had to notice manually. New default flips that to "refuse first, ask explicitly."
- **`--force` flag** — opts into the previous "overwrite + .bak-<ts>" behavior. Pairs with `--no-backup` if you really mean it. `--dry-run` shows the warning block informationally without aborting.
- **README** documents the new retrofit-safety default in the Use section + adds the blocking `[ RETROFIT WARNINGS ]` to the Preflight checks section + lists `--force` in the Flags reference.

This is the first piece of a three-tier retrofit roadmap (logged in `docs/07-backlog.md`, local-only). Tier 2 will add deep-merge for structured assets (`.claude/settings.json`, `.mcp.json`) and skip-and-stage for file collisions; Tier 3 will add a `/retrofit` skill that walks the staged report interactively + a public retrofit guide doc.

## [1.1.0] — 2026-04-24

Second tagged release. Four PRs stacked since v1.0.0, all additive / backward-compatible — no saved `.claude-config.json` from v1.0.0 needs to change. Natural minor bump.

### Changed
- **Select prompt UX clarified.** The prompt for select-type fields was ambiguous — it read `"Pick 1-N or Enter for default [X]"` where `X` was the option value, leaving users unsure whether the input expected a number or the option text. Now reads `"Pick 1-N or type an option name (prefix match); Enter for default [X]"`. Prefix matching was already supported but undocumented.
- **Six free-text fields converted to selects with common choices + `allow_custom: True` fallthrough:** `style.naming`, `stack.database`, `stack.deployment`, `design.architecture`, `design.auth`, `design.observability`. Each now offers 5–11 curated common choices; any input that isn't a number, prefix match, or Enter is accepted verbatim as a custom value (with a confirming print of what was captured). Previous free-text behavior is preserved via the custom path; the prompt just doesn't start empty anymore.

### Added
- **`## Contributing` section in README.** Describes the branch + PR workflow now that `MainBrnchRuleset` enforces PRs + the `check` CI job on every change to `main`. Lists local-verification command (`python3 configure.py --check`) and the canonical `gh` commands for the round-trip.
- **Claude Code version-compatibility preflight.** New `CLAUDE_CODE_COMPAT = {"min_version": "2.1.116", "tested_up_to": "2.1.119"}` in `config_schema.py`, plus a `check_claude_code_version()` helper that shells to `claude --version`, parses, and emits a `[ VERSION WARNINGS ]` block before scaffolding if the installed CC is below min, above tested-up-to, or missing entirely. Silent when in range. Matches the shape of `check_schema_url` / `check_hook_weight` / `check_github_remote`. `--check` success output now also surfaces the compat range. README Requirements section documents the range.
- **`examples/` folder with the first worked scaffold.** `examples/python-uv-fastapi/` holds the full output of `cc-configure` against a Python 3.12 + FastAPI (uv) stack: 27 files under `CLAUDE.md`, `.claude/settings.json`, `.claude/hooks/`, `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, `.gitignore`. Answers the "what does this tool actually generate?" question without requiring installation. `examples/README.md` documents the structure + the regeneration command. A follow-up phase (Item 2 Phase 2 on the backlog) will CI-validate that examples don't drift from current templates.

**Claude Code compat:** 2.1.116–2.1.119

## [1.0.0] — 2026-04-24

First tagged release. The CLI, module catalog, preflight discipline, CI gate, and attribution posture are stable enough to commit to an API.

### Added (after `93cbecd`)

- **`CHANGELOG.md`** — this file. Keep-a-Changelog format, SHA-anchored.
- **Sonatype dependency-management MCP wired into `security-auditor`** via agent frontmatter `mcpServers:` list. Remote HTTP transport against `https://mcp.guide.sonatype.com/mcp` with `Authorization: Bearer ${SONATYPE_TOKEN}`. Scoped to the agent — ~0 context cost when the agent isn't running. Verified against the live docs that agent-frontmatter `mcpServers:` supports the same transport shapes as `.mcp.json` (`stdio`/`http`/`sse`/`ws`).
- **MCP version pinning** across templates + `configure.py`. Every `@latest` / unpinned reference replaced with a specific version verified via Sonatype's recommended-versions lookup. `templates/mcp/servers-cookbook.md` gains a "Pinning discipline" section with the bump procedure and a currently-pinned versions table.
- **`## Acknowledgments` section in the README** crediting the MIT-licensed `PacktPublishing/Agentic-Coding-with-Claude-Code` companion repo for content derived from its code.

### Changed (after `93cbecd`)

- **`docs/00-overview.md` rewritten.** Dropped references to the removed `configurator.html` and to sources whose citations belong in private notes. Added a Modules → docs mapping table, refreshed the numbered-docs list to include `08-memory-hierarchy.md`, added preflight-check discipline to Guiding Principles.
- **`docs/04-subagents-mcp-orchestration.md` patched.** Added concrete MCP-bloat mitigations via `./claude-ctx` + `--strict-mcp-config` with the ~49% → ~2.4% context numbers; refreshed the "Fanout generation" section to point at the shipped `/infinite` + `parallel-generator`; added `/merge-worktrees` pointer in Desktop + cloud.
- **`multi-agent-guardrails.md` reorganized.** Restructured the "when parallel is counterproductive" list around failure modes (race on shared writes / cost > benefit / uncertainty multiplier) and extended to six items (added "active debugging"). Pre-flight checklist extended to five items with "escape hatch" added. Includes a short in-file attribution to the source taxonomy.
- **`/infinite` dispatch protocol renamed.** `uniqueness_directive` → `diversification_axis`; `directory_snapshot` → `claimed_slots_manifest`. The three remaining identifiers (`spec_context`, `iteration_assignment`, `quality_standards`) are generic. Both `templates/commands/infinite/SKILL.md` and `templates/multi-agent/dot-claude/agents/parallel-generator.md` updated consistently.

### Fixed (after `93cbecd`)

- **`@modelcontextprotocol/server-github` end-of-life migration.** Sonatype flagged every version EOL; upstream removed the package from `modelcontextprotocol/servers`. Replaced across `configure.py` `compute_mcp_json()`, `templates/mcp/mcp.json`, and the cookbook with GitHub's official remote HTTP MCP at `https://api.githubcopilot.com/mcp/` using `type: http` + `Authorization: Bearer ${GITHUB_TOKEN}`. Users opt into GitHub MCP via the existing form toggle — the emitted config now produces the working HTTP-transport shape.

## 2026-04-24

### Added
- **`--check` CI gate** (`93cbecd`). `cc-configure --check` runs static validation of templates + `MODULES` registry: paths resolve, JSON parses, `bash -n` passes, `SKILL.md` / agent frontmatter has `name:` and `description:`, `dependsOn:` references are valid. Stdlib-only. Exit 0 on clean, 1 with per-issue summary otherwise.
- **GitHub Actions CI** (`93cbecd`). `.github/workflows/check.yml` runs `--check` plus a dry-run smoke test across every opt-in module (`multi-agent`, `github-actions`, `lockdown`, `experiments-memory`, `mcp`, `ui`) on every push to `main` and every PR. Actions pinned: `actions/checkout@v6`, `actions/setup-python@v5`, Python 3.11.
- **`/verify-setup` skill** (`4a89715`). Audits an already-scaffolded `.claude/` against best practices: CLAUDE.md size, path-scoped rule hygiene, `$schema` URL drift, MCP overhead, hook weight, orphan primitives. Checklist report with concrete next actions; no silent writes.
- **`lockdown` module** (`4a89715`). Opt-in only. Merges `DISABLE_UPDATES=1` into settings `env` — blocks autoupdates *and* manual `claude update`. For air-gapped / enterprise environments.
- **`experiments-memory` module** (`4a89715`). Lazy-loaded `memory/experiments/CLAUDE.md` defines a 5-section format (hypothesis/setup/result/conclusion/follow-ups) for logging experiments. Ships one worked example. Zero context cost until Claude reads files in that folder.
- **`check_schema_url()` drift guard** (`4a89715`). Before scaffolding, verifies the generated settings' `$schema` matches the canonical schemastore URL. Prints `[ SCHEMA WARNINGS ]` block on drift. Guards against the exact regression class that motivated this project.
- **`check_github_remote()` precheck** (`4a89715`). When the `github-actions` module is selected but the target dir isn't a git repo with a GitHub remote, prints `[ MODULE WARNINGS ]` — non-blocking, but users know the Action won't trigger until the remote is set up.
- **`effort: minimal` stamping** (`4a89715`). `eff_effort_minimal` toggle now stamps `effort: minimal` directly into `/check-context`, `/sync-docs`, `/session-retro` frontmatter (placeholder-driven; collapses cleanly when off).
- **Statusline `effort` / `thinking` indicators** (`4a89715`). Appends `| effort <lvl>` and `| think` to the status line when Claude Code 2.1.119+ sends those stdin fields. Older versions render unchanged.
- **Opus 4.7 effort docs note** (`4a89715`). Added to `docs/06-token-efficiency.md` — explains that Pro/Max subscribers on Opus 4.6/4.7 already default to `effort: high`; manual downgrade to `medium` is a false economy.

### Changed
- **Statusline performance** (`93cbecd`). Consolidated five `python3` forks into one using the `CC_STATUSLINE_INPUT` env-var + heredoc pattern. Measured locally: ~103ms → ~31ms per render (−70%). Degrades cleanly on malformed or empty stdin.
- **README rewrite** (`049eb17` / `93cbecd`). Added CI badge, Stack presets table, refreshed Modules table (8 skills in `commands-core`, new modules), Preflight checks section, Requirements split into configurator-runtime vs generated-project deps, Platform support table (Linux / macOS / WSL) with honest Windows-native caveat, `--check` usage in Customizing.

## 2026-04-23

### Added
- **Stack presets** (`ee4cb66`). Tech-stack section now leads with a preset picker (Node + TS / Node + JS / Python uv / Python poetry / Python pip / Go / Rust / Custom). Selecting a preset prefills downstream defaults for package manager, test runner, formatter, typechecker, build tool, and the entire Commands cheatsheet — *before* those fields are prompted. Mirrors the existing `efficiency_preset` pattern.
- **Module dependency resolution** (`ee4cb66`). MODULES can declare `dependsOn: [...]`; `resolve_dependencies()` expands transitively. `commands-core` now depends on `agents`, so `/review`'s `agent: code-reviewer` reference always resolves.
- **`safety.disableBypassPermissionsMode`** (`ee4cb66`). Merges `permissions.disableBypassPermissionsMode: "disable"` — hard-blocks `--dangerously-skip-permissions` for the project.
- **`multi-agent` module** (`4e3fbf9`). Path-scoped guardrails rule (`.claude/agents/**` triggers "when not to parallel" list), `/merge-worktrees` skill (safe integration of parallel branches via disposable branch), `/infinite` skill + `parallel-generator` subagent with multi-section dispatch prompt.
- **`mcp` module profiles + `claude-ctx` wrapper** (`4e3fbf9`). Three per-task profiles at repo root (`.mcp.research.json`, `.mcp.frontend.json`, `.mcp.minimal.json`) and executable `claude-ctx` that runs `claude --mcp-config <profile> --strict-mcp-config`. Book demo: context usage drops 18.8% → 2.4% when scoped.
- **`github-actions` module** (`4e3fbf9`). `.github/workflows/claude.yml` pinned to `anthropics/claude-code-action@v1` (verified from the canonical example; corrected three stale book details: action ref, secret name, `contents: write`).
- **`commands-core` skills** (`4e3fbf9`). Added `/session-retro` (transcript-aware end-of-session retro), `/merge-worktrees` (via multi-agent), `/infinite` (via multi-agent), `/check-context` (flags MCP/skill/memory bloat against the ~49% baseline).
- **`docs/08-memory-hierarchy.md`** (`4e3fbf9`). Documents L1-L5 (enterprise / user / project / path-scoped rules / local) and the "where does this rule go?" decision flow.
- **`multi-agent-guardrails.md`** (`4e3fbf9`). Path-scoped rule file with pre-flight checklist.
- **`statusline-last-prompt.sh`** (`4e3fbf9`). Alternative status line that walks the transcript JSONL reversed and displays the most recent non-slash user prompt.
- **Hook-weight warning** (`ee4cb66`). `check_hook_weight()` flags heavy-interpreter entrypoints (`uv`, `python`, `node`, `poetry`, …) on `PreToolUse` / `PostToolUse` / `PostToolUseFailure` events.
- **"Working with Claude" section in `CLAUDE.md`** (`4e3fbf9`). Five distilled collaboration patterns from Anthropic-team usage: task classification, slot-machine long runs, commit-as-you-go, self-sufficient loops, spec-driven restart. Empty "Tool-calling guardrails" bullets users fill in as quirks surface.

### Fixed
- **`$schema` URL rejection** (`ee4cb66`). `templates/core/dot-claude/settings.json` and `settings.local.json.example` now emit `https://json.schemastore.org/claude-code-settings.json` (was `code.claude.com/schema/settings.json`, which Claude Code's validator rejects silently — dropping all settings).
- **`mcp.json` stale `$schema`** (`ee4cb66`). Removed; no canonical schema exists for `.mcp.json` in schemastore.
- **`commands-core` broken `agent:` reference** (`ee4cb66`). `/review` references `agent: code-reviewer`, but the `agents` module wasn't in the default selection. Fixed via `dependsOn` + default-selection inclusion.

## 2026-04-23 — Pre-takeover baseline

Before the configurator CLI was formalized. Mix of HTML-configurator prototyping (since removed) and initial templates.

- Initial commit (`5e3e47e`)
- Iterated scaffolding (`664b00a` → `8e943ae`)
- **Removed HTML configurator, kept only headless CLI** (`2b32d05` / `8549fd8`)
- Added license (`8717cbb`) and security file (`04c8ea0`)
