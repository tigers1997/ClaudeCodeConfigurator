# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Semantic Versioning from v1.0.0 onward; each entry references its commit SHA.

## Unreleased

### Changed
- **Bumped `CLAUDE_CODE_COMPAT.tested_up_to` from `2.1.121` → `2.1.123`.** Two CC releases came out (2.1.122, 2.1.123); changelog review found no new `settings.json` keys, hook events, or MCP/agent/skill frontmatter fields — bug fixes only (notably 2.1.122's defensive parse: malformed `hooks` entries no longer invalidate the whole settings file, same theme as 2.1.121's enum-validation fix). No template changes required. Users on 2.1.122/123 no longer see the "newer than tested range" `[ VERSION WARNINGS ]` block. README Requirements line updated to match.

## [1.5.0] — 2026-04-28

Sixth tagged release. Theme: **dogfood-driven hardening.** Two new preflight checks driven by feedback from a real install: a `superpowers` `/brainstorm` → `cc-configure` flow on a fresh project surfaced two silent rough edges that this release closes.

`[ DESIGN DETECTED ]` — when the target dir already has design output (`docs/design.md`, `docs/superpowers/`, etc.), the install acknowledges it and the Next-steps printer leads with "fold your design into CLAUDE.md" instead of the brainstorm-bootstrap line the user already followed.

`[ ENV WARNINGS ]` — when an MCP server (or an agent that scopes one) is enabled but its auth token isn't exported, the preflight surfaces it before scaffolding so the silent never-connected failure mode happens never.

Two PRs since v1.4.0, both additive — saved `.claude-config.json` files from any prior version still load.

**Claude Code compat:** 2.1.116–2.1.121

### Added
- **MCP env-var preflight (`[ ENV WARNINGS ]`).** New `check_mcp_env_vars()` in `configure.py` warns when MCP servers (or agents that scope MCPs) are enabled but their required auth tokens aren't set in the running shell. Currently checks `GITHUB_TOKEN` (if `mcp_github` is enabled) and `SONATYPE_TOKEN` (if the `agents` module is selected — `security-auditor` scopes the Sonatype MCP). Non-blocking — files still write — but surfaces the silent-failure mode where the user enables an MCP, never sets the token, and discovers later that the server never connected. Fits the existing four-check preflight pattern alongside version/schema/hook/module checks. Surfaced by dogfood feedback ("`security-auditor`'s Sonatype MCP needs SONATYPE_TOKEN env var to activate" — was a manual catch).
- **Brainstorm-aware install** — `configure.py` now scans the target dir for prior design output (`docs/design.md`, `docs/spec.md`, `docs/plan.md`, anything under `docs/superpowers/`) and emits a `[ DESIGN DETECTED ]` info block before scaffolding when found. The Next-steps printer then leads with "Fold project-wide invariants from <path> into CLAUDE.md" instead of the brainstorm-bootstrap line — the user already did the brainstorming. Closes the gap surfaced by dogfood feedback where the configurator wrote a generic CLAUDE.md against a project that had been through `superpowers` `/brainstorm` and produced a design doc.

## [1.4.0] — 2026-04-28

Fifth tagged release. Theme: **schema unblocks.** Two settings keys that the configurator had been holding in `docs/07-backlog.md` because schemastore would reject them are now validated and shipped as opt-ins, plus tracking-up to the current Claude Code release.

`prUrlTemplate` (CC 2.1.119) — non-GitHub hosts now get correct PR badges in the footer and tool-result summaries. `sandbox.network.deniedDomains` (CC 2.1.113) — defense-in-depth for users with sandboxing enabled, with a paste/file-drop denylist baseline. Both are commented-out by default per the configurator's comment-key discipline; uncomment to opt in.

Three PRs since v1.3.0, all additive — saved `.claude-config.json` files from any prior version still load.

**Claude Code compat:** 2.1.116–2.1.121

### Added
- **`prUrlTemplate` opt-in in `git-workflow` module.** Schemastore-validated as of 2026-04-28 (CC 2.1.119+); previously held due to schema-rejection risk. Adds a commented-out `prUrlTemplate` template to `templates/git-workflow/settings-patch.json` with example URL templates for GitLab, Bitbucket, and GitHub Enterprise. User uncomments + substitutes their host. Footer PR badges and tool-result summaries render against the template instead of always pointing at github.com. Comment-keyed (`"// prUrlTemplate"`) so the value is stripped at scaffold time per the existing comment-key discipline; setting takes effect only when the user explicitly opts in.
- **`sandbox.network.deniedDomains` opt-in in `safety` module.** Schemastore-validated as of 2026-04-28 (CC 2.1.113+); previously held due to schema-rejection risk. Adds a commented-out `// sandbox` block to `templates/safety/settings-patch.json` with a 10-entry data-exfiltration-resistant baseline (paste services + file-drop services: pastebin, paste.ee, hastebin, ix.io, 0x0.st, bashupload, transfer.sh, file.io, anonfiles, uguu.se). Supports wildcards (`*.example.com`). User uncomments + tunes for their threat model. Only takes effect when the sandbox is otherwise active for the command — pure belt-and-suspenders for users with sandboxing enabled.
- **`alwaysLoad` MCP tuning knob documented in `templates/mcp/servers-cookbook.md`.** Claude Code 2.1.121 added an `alwaysLoad: true` boolean to MCP server config that bypasses tool-search deferral. Cookbook documents the trade-off (re-burns tokens that deferral was suppressing; only worth it for servers whose tools you call every turn) and recommends `claude --mcp-config <profile> --strict-mcp-config` (the existing `claude-ctx` wrapper) as the cleaner choice for guaranteed loading of one tool group.

### Changed
- **Bumped `CLAUDE_CODE_COMPAT.tested_up_to` from `2.1.119` → `2.1.121`.** Two CC releases came out (2.1.120, 2.1.121); the configurator's templates now verify clean on the current Claude Code. Users on 2.1.120/121 no longer see the "newer than tested range" `[ VERSION WARNINGS ]` block. README Requirements section updated to match.

## [1.3.0] — 2026-04-27

Fourth tagged release. Theme: **the configurator is part of an ecosystem, not an island.** Three PRs since v1.2.0, all additive — saved `.claude-config.json` files from any prior version still load.

The headline: new projects get routed through `superpowers` brainstorming before scaffolding (design-first discipline), retrofits get pointed at the `/retrofit` skill, and every project gets a stack-aware `docs/recommended-plugins.md` listing the official Claude Code plugins worth installing alongside the configurator's deterministic baseline. The configurator stops competing with `feature-dev` / `commit-commands` / `claude-md-management` and starts complementing them.

**Claude Code compat:** 2.1.116–2.1.119

### Added

- **`docs/11-getting-started.md`** — two end-to-end walkthroughs framing the configurator's place in a project's lifecycle. **New-project flow** prefixes scaffolding with `superpowers` brainstorming: `claude /plugin install superpowers` → `/brainstorm` (hard-gates implementation until a design is approved) → capture to `docs/design.md` → `cc-configure` shaped by the design → install stack-specific plugins from the auto-generated recommendations doc. **Retrofit flow** documents the `--dry-run` → `cc-configure` → review `[ MERGED ]` / `[ COLLISIONS ]` → `/retrofit` skill → cleanup pattern. Plus daily-use mappings between configurator skills and their official-plugin equivalents.
- **`docs/10-plugin-ecosystem.md`** — strategic positioning doc. Comparison table: which configurator surfaces have plugin equivalents (`commands-core` skills ↔ `feature-dev` + `commit-commands`; `code-reviewer` agent ↔ `feature-dev`'s version; `safety` hooks ↔ `security-guidance` + `hookify`; `/sync-docs`/`/session-retro` ↔ `claude-md-management`). Where each side stays unique (configurator: form-driven intake, retrofit safety, preflight architecture; ecosystem: vendor integrations, recency, the `claude-automation-recommender`). Recommended dual-stack workflow + swap path for users who want plugin equivalents.
- **`recommend-plugins` module** (in default selection). Generates `docs/recommended-plugins.md` with stack-aware plugin recommendations from the user's form answers. Static "always-recommended" block: `claude-code-setup`, `claude-md-management`, `feature-dev`, `commit-commands`, `superpowers`. Stack-specific block from `compute_recommended_plugins()`: language → LSP plugin; database → DB plugin (`mongodb` / `neon` / `prisma` / `cloud-sql-postgresql` / `supabase` / `cockroachdb` / `pinecone`); framework → framework plugin (`frontend-design` / `vercel` / `expo` / `rails-query` / `laravel-boost` / `shopify-ai-toolkit`); MCP toggles → official MCP replacements (`github` / `playwright` / `context7`); deployment → cloud plugin (`aws-serverless` / `azure`); observability → APM plugin (`sentry` / `datadog` / `logfire`). Refreshes on every `cc-configure` run.
- **Context-aware "Next steps" output**. After scaffolding, the printed guidance branches on whether the run was a retrofit (any `[ MERGED ]` or `[ COLLISIONS ]` entries fired) or fresh. New-project guidance prefixes steps with the `superpowers` brainstorming bootstrap and points at `docs/recommended-plugins.md`. Retrofit guidance points at `/retrofit` and the `.claude-retrofit/` cleanup pattern. Both link to `docs/11-getting-started.md`.

### Internal

- New helper `compute_recommended_plugins(form_values)` in `configure.py`. New placeholders `{{recommended_plugins}}` and `{{generation_date}}` wired into `compute_placeholders`. New `target_path_for` route for `recommend-plugins/recommended-plugins.md` → `docs/recommended-plugins.md`. README repo-layout count bumped 9 → 10 → 11 (now 11 numbered docs).

## [1.2.0] — 2026-04-27

Third tagged release. The retrofit-safety theme: a sophisticated existing project (your 370-line CLAUDE.md, custom hooks, custom skills, custom MCP servers) is now first-class. Six PRs stacked since v1.1.0, all additive / backward-compatible — saved `.claude-config.json` files from v1.1.0 still load unchanged. Natural minor bump.

The headline: running `cc-configure` against an existing project no longer clobbers anything. Structured assets deep-merge automatically; CLAUDE.md gets the value-add sections appended; skill/agent/rule/hook collisions stage to `.claude-retrofit/incoming/` for review. A new `/retrofit` skill walks the staged report interactively. Three-tier roadmap delivered end-to-end.

**Claude Code compat:** 2.1.116–2.1.119

### Added

- **`/retrofit` skill** (`commands-core`) — walks `.claude-retrofit/REPORT.md` interactively. Per Skipped staging: shows diff, offers Keep/Replace/Merge/Rename/Skip, applies with `.bak-retrofit-<date>` backups before any destructive op, removes handled stagings. Discipline encoded explicitly (no auto-picks, no silent merges, no clobbers without backup). Edge cases handled (missing yours; identical files; no REPORT.md; structurally-incompatible merge → recommend rename instead).
- **`docs/09-retrofit-guide.md`** — five-bucket triage doc: what belongs in `CLAUDE.md` vs. `.claude/rules/<scope>.md` (path-scoped) vs. `docs/<topic>.md` vs. issue tracker vs. delete-because-it's-already-in-the-repo. Linked from `00-overview.md` (now 8 numbered docs) and the README's Use section.
- **`--claude-md={append|skip|overwrite}` flag** (default `append`) — handles CLAUDE.md collisions specifically. Append finds the three value-add sections (`## Working with Claude (collaboration patterns)`, `## Claude Code behavior rules`, `## Token efficiency rules`) in the generated CLAUDE.md and appends any missing ones to your existing file. Idempotent on re-runs; same-heading-different-content treated as "user has it" and skipped.
- **`--on-collision={skip|rename|overwrite}` flag** (default `skip`) — handles file-based asset collisions (skills, agents, rules, hooks). `skip` stages ours to `.claude-retrofit/incoming/<path>` and a structured `REPORT.md` for manual review. `rename` installs ours as a `-cc`-suffixed sibling (e.g. `review-cc/`) so both coexist. `overwrite` replaces yours with `.bak-<ts>` backup.
- **Deep-merge for `.claude/settings.json` and `.mcp.json`** — automatic, always-on (unless `--force`). Your customizations win on collisions (preserves explicit choices); canonical `$schema` and security-default `disableBypassPermissionsMode` get ours; permissions/hooks/env unioned with sensible per-key strategies; unknown top-level keys pass through. New `[ MERGED ]` and `[ COLLISIONS ]` informational blocks summarize what happened.
- **`.claude-retrofit/REPORT.md`** — written automatically when there are merges or collisions. Structured tables per action class with diff coordinates. Seeds the `/retrofit` skill.
- **Dry-run output distinction** — `~` for merged files vs `+` for net-new.
- **README Resolving-staged-conflicts subsection** — points at `/retrofit` (guided) and the retrofit guide (manual + triage discipline).

### Changed

- **Default behavior on existing projects is now non-destructive.** Pre-v1.2.0: blanket overwrite-with-backup (then in v1.1.x→v1.2.0-rc the Tier 1 path: refuse-or-`--force`). v1.2.0: structured assets deep-merge automatically; CLAUDE.md merge-appends; file collisions skip-and-stage. Net effect — running on existing projects "just works" in the safe direction. `--force` is the kill-switch for users who want the old overwrite-everything behavior.
- **Stop hook now uses your form-configured commands**, not hardcoded JS tooling. `templates/git-workflow/hooks/stop-run-checks.sh` previously hardcoded `npx --no-install tsc`/`eslint`/`vitest`, which broke silently for any non-JS project — `command -v npx` succeeds on most dev machines, but the actual tools aren't there, so every Stop fired a FAIL report. The hook now substitutes `{{cmd_typecheck}}` / `{{cmd_lint}}` / `{{cmd_test}}` from the intake form, so a `Python (uv)` preset produces `uv run mypy .` / `uv run ruff check` / `uv run pytest`. Empty-after-substitution commands skip silently — blanking a field in the form is now the way to say "I don't have a typecheck/lint/test setup." The existing runtime `command -v <first-token>` defense-in-depth check is preserved.

### Internal

- New helpers in `configure.py`: `_merge_unique_list`, `deep_merge_settings`, `deep_merge_mcp`, `apply_structured_merges`, `collision_renamed_target`, `apply_file_collision_strategy`, `write_retrofit_report`, `VALUEADD_HEADINGS`, `_extract_section`, `_append_missing_valueadd_sections`, `apply_claudemd_strategy`. Dead `check_retrofit_state` helper from the v1.2.0-rc Tier 1 abort path removed.

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
