# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Semantic Versioning from v1.0.0 onward; each entry references its commit SHA.

## Unreleased

- **feat(safety): package-availability gate + OS/tool-version status-line chip.** New PreToolUse Bash hook `safety/hooks/check-package-availability.sh` hard-denies `apt|apt-get|brew|dnf|yum|pacman|apk install` commands when the target packages aren't in any configured repo. Structured denial message lists missing packages, related siblings found via per-PM regex search (up to 8), the detected installed major version of the same family (e.g., `PostgreSQL 17.4` when blocking `postgresql-18`), three concrete next-step options, and a stale-cache warning when `/var/lib/apt/lists/` is older than 7 days. Shared bash libs land at `templates/safety/hooks/_lib/` (`availability_check.sh`, `detect_tool_versions.sh`) — the first reusable across hooks, the second consumed by the status line. UI module's `templates/ui/statusline.sh` now appends an OS+tool-version chip (`deb13 · pg17 · node20 · py3.13 · docker27`) by sourcing `detect_tool_versions.sh` per render; new `ui.no_version_chip` flag emits `CC_STATUSLINE_NO_VERSION_CHIP=1` for opt-out. Hook is fail-open by design: composite shell expressions (`|`, `&&`, `;`, `$()`, backticks), globs, brace expansion, shell variables, file installs (`./local.deb`, `*.rpm`, `*.apk`), missing `jq`, slow probes (>3s `timeout`), and any internal error (ERR trap) all bail with stderr note and exit 0. Per-probe time bound at 3s. Always-declared `pkgs`/`missing`/`pm` state lets `_log_decision` (JSONL writer to `.claude/logs/availability-check.log`) run safely from ERR trap before parsing. v1 covers OS package managers only — language PMs (pip/npm/cargo/gem/go) and download-URL freshness are tracked for follow-up PRs; URL freshness in particular has a high false-positive rate at the network level and is deferred until a semantic check exists. New `test/availability-check/` directory with 19 fixture tests (TDD-developed per the brainstormed spec/plan) covers the per-PM probes, the chip with/without stub fixtures, the JSON-parse decision matrix, every parser bailout, hook regressions (sudo + env stripping, value-taking flags like `-t bookworm-backports`, version pins, multi-pkg with mixed available+missing), error handling (jq missing, malformed JSON, stale cache), and JSONL logging conditionality on `.claude/logs/` presence. CI gains an `Install jq` step + `Availability-check hook tests` loop in `.github/workflows/check.yml`. Persona snapshots regenerated for all four personas that ship `safety/` (custom unchanged). Spec + plan in `docs/superpowers/specs/2026-05-27-package-availability-gate-design.md` and `docs/superpowers/plans/2026-05-27-package-availability-gate.md` (gitignored, local-only per PR #50).
- **feat(license): relicense from MIT to AGPL-3.0 with discipline-skills MIT carve-out.** The configurator's own code (configure.py, config_schema.py, all original templates, hooks, docs, tests, examples) switches to GNU Affero General Public License v3.0 to close the SaaS loophole that lets hyperscalers fork permissive copyleft projects into closed managed services without contributing back (the "MongoDB on AWS" pattern that drove MongoDB→SSPL, Elastic→ELv2/SSPL, and HelixDB's 2025-05-13 GPL→AGPL switch — the proximate model for this change). Network-served modifications now trigger AGPL-3.0 source-distribution requirements. **Carve-out:** `templates/discipline-skills/` keeps its MIT License (© 2025 Jesse Vincent, forked from obra/superpowers v5.1.0) — the MIT terms travel with those files when users install the module into their projects; the surrounding configurator code is AGPL-3.0; MIT is compatible with AGPL aggregation. New root `NOTICE` documents the bundled-license breakdown. README `## License` section rewritten to explain the change + carve-out + irrevocability of past MIT releases. AGPL-3.0 added to the user-facing license picker in `config_schema.py` (between Apache-2.0 and GPL-3.0) so users can select it for their own projects. `test/discipline-skills/test-license-attribution.sh` continues to pass (validates the MIT carve-out, not the root license). Past tagged releases remain MIT under their original terms; AGPL-3.0 applies to all subsequent commits.
- **fix(retrofit): dedupe hook groups so repeated `cc-configure --retrofit` stops inflating settings.json.** `deep_merge_settings` historically concatenated hook groups onto the existing list without dedup (configure.py:1149-1151 docstring). The rationale ("preserve user customizations that happen to share a matcher") held when the existing hooks were genuinely user-authored, but broke on retrofit — where the existing hooks are CONFIGURATOR-shipped from a prior scaffold. After N retrofits, every configurator hook fires N+1 times. Dogfood empirically confirmed: a fresh `solo-experienced` scaffold has 3 PreToolUse + 3 PostToolUse + 1 Stop + 4 SessionStart hook groups; after 3 retrofits those inflate to 12, 12, 4, 16 respectively. Fix: hook-list merge now goes through the existing `_merge_unique_list` helper (which already handles permissions.allow/ask/deny correctly) — structural equality via Python's `==` on dicts. Self-healing: a user whose settings.json already accumulated N duplicates from prior versions sees them collapse back to 1 on their next retrofit (the merged list gets re-deduped against itself). User customizations survive: a hook group with a different matcher, different command, or different timeout is structurally distinct from configurator-shipped ones and is preserved. New `test/retrofit-hooks/` directory with 3 fixtures: no-op retrofit doesn't inflate; prior-buildup collapses on next retrofit; three flavors of user customization all preserved across retrofit. Known limitation (out of scope): when the configurator changes a shipped hook between releases (e.g., bumps a timeout from 5→10), the user's old version + new version both survive structural dedup. Rare in practice; same-release retrofits — the dominant case — are fully fixed. Future fix would track configurator provenance per hook group (e.g., a marker field), but that conflicts with the schema-hygiene retired `//` pattern from PR #60.
- **fix(schema-hygiene): retire //-stub pattern + drop unvalidatable skillOverrides default + add settings preflight.** Dogfood from upgrading an adjacent project surfaced two real validator-rejection bugs introduced by PRs #17, #18, #56, and #57: (1) `templates/token-efficiency/settings-patch.tier-pro.json` shipped `"skillOverrides": "name-only"` (string form), but the current Claude Code schema requires the per-skill object map (`{"skill-name": "name-only"}`) and rejects the string — `name-only` was a legacy/imagined "apply to all skills" form that the official doc never sanctioned; further, per code.claude.com/docs/en/settings the setting doesn't apply to plugin skills at all, narrowing its usefulness as a tier-wide default; (2) the `// foo` "commented opt-in stub" pattern (`// sandbox`, `// env`, `// prUrlTemplate`, `// worktree`, `// subagentStatusLine`, `// hideVimModeIndicator`) propagated as literal top-level keys into the user's `.claude/settings.json`, where Claude Code's editor schema validator flags them as unknown properties. The design intent (PR #56's `_is_doc_label` filter) was to keep `// foo` stubs and strip only bare `//` / `//N` doc labels; the dogfood proves the intent was wrong. **Fixes:** `_is_doc_label` now strips ALL `//`-prefixed keys; new `_strip_doc_labels` recursively scrubs the merged settings before render (catches nested cases like `statusLine.// hideVimModeIndicator` that the shallow per-merge filter missed); `extraSettings` merge path now applies the filter (was previously bypassed — UI module's bare `"//"` was leaking too); `skillOverrides: "name-only"` deleted from tier-pro (replaced with a docstring explaining why no default ships); all `// foo` stubs deleted from source patch files (`safety/settings-patch.json`, `multi-agent/settings-patch.json`, `git-workflow/settings-patch.json`) and from the ui module's inline `extraSettings`; opt-in discovery moved to `templates/core/dot-claude/settings.local.json.example` (the `.example` suffix means Claude Code doesn't parse it directly, so `// foo` stubs there are safe). New `check_settings_validates()` preflight catches both bug classes at scaffold time + emits a `[ SETTINGS WARNINGS ]` block; new static `--check` step asserts no settings-patch ships `skillOverrides` as a non-object (regression guard, caught the current bug when run for the first time). New test directory `test/schema-hygiene/` with 4 fixtures: cross-persona no-leak assertion, source-patch shape assertion, preflight-detects-violations (4 violation classes + clean case), recursive `_strip_doc_labels` invariant. Compat note: users on cc-configure 2.6.0 + a populated `.claude/settings.json` get the cleanup on next `cc-configure --retrofit` — the deep-merge preserves their customizations and the new strip removes the stub-leaks.
- **feat: discipline-skills module — curated 7-skill subset forked from obra/superpowers v5.1.0.** New `templates/discipline-skills/` module ships seven discipline skills as project-level `.claude/skills/<name>/SKILL.md`: `brainstorming`, `writing-plans`, `executing-plans`, `verification-before-completion`, `using-git-worktrees`, `subagent-driven-development`, `finishing-a-development-branch`. Forked verbatim from the MIT-licensed upstream plugin with three surgical edits: visual-companion section stripped from `brainstorming` (the upstream's browser-based companion server is omitted — text-only mode is the default fallback anyway); `superpowers:` prefix stripped from every inter-skill cross-reference so they resolve correctly as project-level skills; the `requesting-code-review` template embedded inline into `subagent-driven-development/code-quality-reviewer-prompt.md` and the cosmetic `test-driven-development` companion line dropped from `subagent-driven-development/SKILL.md`'s Integration section. Module includes a slim SessionStart bootstrap (`hooks/sessionstart-discipline.sh`) that primes the model with a ~400-token seven-skill overview (vs. upstream's ~1,200-token `using-superpowers` injection) and auto-suppresses when the upstream `superpowers` plugin is also installed (detects `~/.claude/plugins/cache/claude-plugins-official/superpowers/`). Wired into `config_schema.py` with `extraSettingsHook` for the SessionStart registration and into the `solo-newer`, `solo-experienced`, `small-team` personas by default. Upstream MIT LICENSE ships at `.claude/skills/_LICENSE-discipline-skills.md`; attribution to Jesse Vincent (© 2025) added under README `## Acknowledgments`. New `/verify-setup` Check #12 flags duplicate installation (both the configurator's module and the upstream plugin present) so users can pick one. New `docs/10-plugin-ecosystem.md` section "Discipline skills: bundled vs. upstream plugin" documents the trade-off (~930 tokens saved per session vs. losing access to the 7 unused upstream skills) and the maintainer-internal `templates/discipline-skills/SYNC.md` documents the upstream-sync workflow. Recommend-plugins copy reframes the upstream `superpowers` row as the "full-suite alternative" rather than the configurator's first-choice recommendation.

### Added

- `CONTRIBUTING.md` — AGPL-aware contributor flow with "Your rights as a contributor" section, license-compatibility checklist, and branch-protection contract. (#64, 96a8d95)
- `CODE_OF_CONDUCT.md` — Contributor Covenant 2.1, enforcement contact matches `SECURITY.md`. (#64, 96a8d95)
- `.github/CODEOWNERS` — sensitive-surface map (legal substrate, CI integrity, discipline-skills MIT carve-out, core engine paths). (#64, 96a8d95)
- `.github/pull_request_template.md` — checklist mapped 1:1 to required CI checks. (#64, 96a8d95)
- `README.md` Contributing section shrunk to a pointer; the substance moved to `CONTRIBUTING.md`. (#64, 96a8d95)
- `.github/workflows/review.yml` — AGPL-aware AI code-review gate via `anthropics/claude-code-action@v1` running `claude-sonnet-4-6`. The `ai-review` job runs the action in agent mode (`prompt:` set); Claude reads CONTRIBUTING/CHANGELOG + the PR diff via `gh pr diff`, then posts ONE PR conversation comment beginning with `VERDICT: PASS|BLOCK|COMMENT-ONLY` using `gh pr comment`. The follow-up `verdict-gate` job (always() so it runs even if ai-review fails) paginates `repos/$REPO/issues/$PR_NUMBER/comments`, picks the latest `VERDICT:` line, and fails the workflow on `BLOCK` or missing-VERDICT so branch protection can require `review` as a status check. Self-bootstrap escape hatch: when the PR diff modifies `review.yml` itself, `verdict-gate` soft-passes (GitHub's workflow-modification safety skips the action, leaving no comment to parse — without this, every workflow-edit PR would have a permanently-red gate). Manual re-trigger via `@claude review` PR comment. Drafts skipped. Action v1 input shape (no deprecated `model`/`allowed_tools` direct inputs — both moved under `claude_args` as `--model` and `--allowedTools`, camelCase per CLI reference). (#65, 98b00f5)
- `docs/governance/branch-protection.json` — exported `MainBrnchRuleset` so the branch-protection contract is reproducible from version control. Re-export and re-commit on every ruleset change.

### Changed

- `MainBrnchRuleset` ratcheted to load-bearing state. Required status checks expanded from `check` alone to `check` + `ai-review` + `verdict-gate` (and `license/cla` to be added once cla-assistant.io establishes the check name on the first contributor PR). Newly required: signed commits (GPG or SSH), linear history, conversation resolution before merge, branch-deletion blocked, force-push blocked. Bypass actors list emptied — the maintainer is bound by the gate. Cla-assistant.io GitHub App installed with the SAP Individual CLA template.
- `CONTRIBUTING.md` — § "Your rights as a contributor" names the SAP Individual CLA explicitly; § "Opening a PR" lists the four required status checks (`check`, `ai-review`, `verdict-gate`, `license/cla`) with their exact roles; § "The review gate" rewritten to describe the agent-mode comment-posting flow + the verdict-gate parsing + the self-bootstrap escape hatch for workflow-modifying PRs; § "Branch protection contract" updated to match the ratcheted ruleset (signed commits, linear history, conversation resolution nested under PR-required, empty bypass actors).

Bundle release: the SchemaStore PR #5706 unblock batch — PR #56 shipped eight schema-validated CC 2.1.143 settings keys + bumped `tested_up_to` 2.1.132 → 2.1.150 (closing tracking issue #53 after a multi-month, three-resurvey watch on the upstream gating PR), and PR #57 followed up by promoting two of those opt-ins to active defaults after a per-key review against the configurator's safety/efficiency goals. Latent strip-bug fix in #56 also unblocked the existing PRs #17/#18 opt-ins (`// prUrlTemplate`, `// sandbox.network.deniedDomains`) — they now actually surface in users' generated `.claude/settings.json` for the first time. `CC_VERSION` bumped to 2.6.0.

### v2.6.0 — CC 2.1.150 schema-validated keys batch + active-default promotions

**The pattern:** the configurator wraps every Claude Code primitive it depends on behind a JSON-schema-validation gate — when a CC settings key isn't yet in `claude-code-settings.json` (community-maintained in SchemaStore/schemastore, Anthropic-CODEOWNED), shipping a template that uses it risks Claude Code silently dropping adjacent sections at parse time. v2.6.0 lands the long-tail unblock batch for SchemaStore PR #5706 (merged 2026-05-23, syncing to CC v2.1.143) — eleven configurator-territory keys + five env vars that had been held in `docs/07-backlog.md` through three CHANGELOG resurveys (2026-05-06, 2026-05-11, 2026-05-21) plus a fourth resurvey of 2.1.147–2.1.150 to capture anything new.

- **feat(compat): ship 8 schema-validated opt-ins + fix latent // strip; bump tested_up_to 2.1.132 → 2.1.150 (PR #56).** The full unblock batch closes tracking issue [#53](https://github.com/tigers1997/ClaudeCodeConfigurator/issues/53). Eight new opt-ins land across `safety`, `multi-agent` (which previously shipped no settings — gained its first `settingsPatch` reference + a new `templates/multi-agent/settings-patch.json`), `ui` (via `extraSettings` since it predates `settingsPatch`), and `token-efficiency` (in the existing tier-pro patch). All shipped as commented `// keyname` stubs matching the PRs #17 (`prUrlTemplate`) / #18 (`sandbox.network.deniedDomains`) precedent — users uncomment to activate. Settings keys: `skillOverrides` (CC 2.1.129+, token-efficiency-pro), `worktree.baseRef` + `worktree.bgIsolation` (CC 2.1.133+ / 2.1.143+, multi-agent), `autoMode.hard_deny` (CC 2.1.136+, safety), `sandbox.failIfUnavailable` (CC 2.1.143+, nested inside the existing `// sandbox` block in safety), `subagentStatusLine` + `statusLine.hideVimModeIndicator` (CC 2.1.143+, ui), and `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (CC 2.1.143+, safety env). Hook `args: string[]` exec form + `continueOnBlock: boolean` (CC 2.1.139+) shipped as doc notes in `safety` + `git-workflow` patches — no active hooks use them; forward-looking enablement for user-authored hooks. Four other env vars (`ANTHROPIC_WORKSPACE_ID`, `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE`, `CLAUDE_CODE_PLUGIN_PREFER_HTTPS`, `CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY`) are platform-/workspace-specific and captured only in the `CLAUDE_CODE_COMPAT` rationale comment. Still held for a future schemastore sync: hook output `terminalSequence` (CC 2.1.147) and Stop/SubagentStop hook input `background_tasks` + `session_crons` (CC 2.1.149) — both verified absent from #5706's head-branch schema. **Latent bug fix:** `configure.py:463` had been stripping ALL top-level `//`-prefixed keys when merging `settingsPatch` files, including the opt-in stubs PRs #17 and #18 promised would surface in `.claude/settings.json`. New `_is_doc_label(k)` helper distinguishes label keys (`//`, `//N`) from stub keys (`// foo`). Existing `// sandbox` + `// prUrlTemplate` now appear in scaffolded outputs for the first time — users on `cc-configure --retrofit` will see them. Two source patches also corrected (`safety/settings-patch.slop-scan.json`, `commands/microbit-enforcer/settings-patch.json`) — their top-level descriptive `// filename.json` keys would have leaked into user settings under the new filter; rewritten as plain `"//"` labels.
- **feat(defaults): promote skillOverrides + autoMode.hard_deny to active defaults (PR #57).** Per-key review of the eight new opt-ins from #56 against the configurator's existing safety/efficiency goals: six stay stubbed for genuine reasons (user-workflow choice, infrastructure-dependent, or would break shipped scripts), two get promoted. `skillOverrides: "name-only"` is now active in `templates/token-efficiency/settings-patch.tier-pro.json` (renders only when `tier=pro`) — extends the pro tier's existing aggressive-efficiency contract by collapsing skill descriptions (the largest per-turn context overhead, exactly the metric `/check-context` flags). Model still sees skill names; only descriptions are trimmed. `autoMode.hard_deny: ["Running executable files", "Writing to system directories"]` is now active in `templates/safety/settings-patch.json` — pure upside since the auto-mode classifier doesn't fire without `--auto-mode` (no-op for manual sessions, meaningful safety backstop for auto-mode users), consistent with the configurator's existing safety posture (`disableBypassPermissionsMode: disable`, scan-secrets, slop-scan). Retrofit impact: existing users get a top-level `autoMode` block (all non-custom personas) and pro-tier users (`solo-experienced` + `small-team`) get a top-level `skillOverrides: "name-only"`. Both are no-ops in common workflows. Six stubs retained with rationale captured inline in the patch comments — promotable in future PRs as the underlying constraints lift (`statusline.sh` learning `--subagent` or vim mode; a `safety.sandbox_strict` flag for `failIfUnavailable`; etc.).

---

**Claude Code compat:** bumped to 2.1.116–2.1.150 (was 2.1.116–2.1.132 in v2.5.0). 18 CC releases covered since the prior bump; SchemaStore PR #5706 sync to CC v2.1.143 merged 2026-05-23 unblocking the long-held key batch. Final 2.1.147–2.1.150 resurvey found one new key (`allowAllClaudeAiMcps`, 2.1.149) — Enterprise managed setting, outside configurator territory.

## [2.5.0] — 2026-05-21

Bundle release: the drift-monitor family — PR #51 introduced the pattern (`.claude/.cc-manifest.json` baseline + SessionStart hook + `/verify-setup` narrative for MCP servers), and PR #54 completed it with two more dimensions (stack manifests + check-command alignment). Plus PR #49 cleaning up legacy `/brainstorm` references after the superpowers v5.1.0 churn, and PR #52 tracking SchemaStore PR #5706 (no template changes; `tested_up_to` bump deferred to the unblock batch). `CC_VERSION` bumped to 2.5.0.

### v2.5.0 — drift-monitor family

**The pattern:** cc-configure had historically been a one-shot scaffolder. After running, the configured `.claude/`, `.mcp.json`, `CLAUDE.md` could drift from project reality (new MCP servers added, language stack shifted, test runner changed) and the configurator had no in-session signal — the user only noticed when something visibly broke. v2.5.0 introduces the **drift monitor** primitive: a versioned baseline file written at scaffold/retrofit time + a SessionStart hook that diffs baseline vs. live and emits one terse line per drifted dimension + `/verify-setup` sub-checks that narrate the diff and propose a fix (`cc-configure --retrofit`). Three dimensions ship in this release, all using the same `.claude/.cc-manifest.json` baseline:

- **feat: MCP drift monitor — SessionStart hook + `.cc-manifest.json` baseline + manifest-aware `/verify-setup` Check #4 (PR #51).** cc-configure now stays alive between runs: every scaffold/retrofit writes `.claude/.cc-manifest.json` snapshotting the `.mcp.json` server set; a new SessionStart hook (`.claude/hooks/sessionstart-drift-check.sh`, installed by the `mcp` module) compares manifest vs. live `.mcp.json` on `startup`/`resume` and emits one stdout line if servers were added or removed since the last cc-configure run; the line points to `/verify-setup`, whose Check #4 was rewritten to enumerate per-server purpose, cost class, profile-split fit, and a supply-chain vetting nudge (parses `npx`/`uvx` package coordinates and recommends the user invoke the available Sonatype MCP tools — `getComponentVersion`, `getLatestComponentVersion`, `getRecommendedComponentVersions` — before keeping any new MCP). Manifest writer is unconditional (runs even when the `mcp` module isn't selected, so a forward-looking baseline always exists); hook is module-gated. New `[ MANIFEST WARNINGS ]` block surfaces unreadable `.mcp.json` without ever locking in a corrupt baseline. New test directories: `test/cc-manifest/` (5 tests + e2e lifecycle), `test/sessionstart-drift-check/` (9 hook-behavior fixtures). New verify-setup spec-presence test pins the Check #4 anchors. Spec + plan: `docs/superpowers/specs/2026-05-13-cc-configure-mcp-drift-monitor-design.md` and `docs/superpowers/plans/2026-05-13-cc-configure-mcp-drift-monitor.md` (gitignored, local-only working artifacts).
- **feat: stack-alignment monitor — manifest schema v2 + two new SessionStart drift dimensions + `/verify-setup` §4b/§4c (PR #54).** Extends the MCP drift monitor with two more dimensions: **stack drift** (compares the set of repo-root stack manifests — `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `pom.xml`, `build.gradle` — at scaffold time vs. now) and **command alignment** (checks that the first binary of each configured `cmd_typecheck`/`cmd_lint`/`cmd_test` still has a matching stack manifest in the repo). `.claude/.cc-manifest.json` bumps to `manifest_version: 2` with two new fields (`stack_manifests`, `check_commands`); the SessionStart hook (`sessionstart-drift-check.sh`) gains §2 + §3 emitting one terse line per drifted dimension, all pointing at `/verify-setup`. `/verify-setup` gains §4b + §4c narrative blocks. Compatibility: v2 hook reads v1 manifests as if the new fields were empty (no false drift on PR #51 baselines); v1 hook seeing a v2 manifest fires the existing version-skew nudge. §3 carries a pre-bootstrap skip (configured binary's expected manifest must have been in the baseline `stack_manifests` set) so brand-new scaffolds on empty dirs stay silent — same spirit as the stop-hook manifest-missing skip rule from v2.4.0. New helpers: `detect_stack_manifests()`, `extract_first_binaries()` in `configure.py`. New tests: `test/cc-manifest/test-stack-manifests-detected.sh`, `test/cc-manifest/test-check-commands-extracted.sh`, seven new `test/sessionstart-drift-check/test-*.sh` fixtures, `test/verify-setup/test-stack-alignment-spec-present.sh`. Spec + plan: `docs/superpowers/specs/2026-05-21-stack-alignment-check-design.md` and `docs/superpowers/plans/2026-05-21-stack-alignment-check.md` (gitignored, local-only working artifacts).

**Housekeeping:**

- **docs: drop legacy `/brainstorm` + `/write-plan` references after superpowers v5.1.0 (PR #49).** `superpowers` v5.1.0 (2026-04-30) removed the `/brainstorm`, `/write-plan`, and `/execute-plan` slash commands — they were deprecated stubs and users must now invoke the skills directly (or just describe the work; the SessionStart bootstrap auto-routes). Configurator references updated: `configure.py` "Next steps" output now says "describe what you want to build" instead of "invoke /brainstorm"; `docs/11-getting-started.md` walkthrough swaps the explicit `> /brainstorm` prompt for plain-English intent and adds an inline note about the v5.1.0 removal; `docs/10-plugin-ecosystem.md` install snippet drops `claude /brainstorm`; `templates/recommend-plugins/recommended-plugins.md` row reframes the gate as skill-driven. Historical CHANGELOG entries unchanged (they reference what was current at the time).
- **chore(compat): survey Claude Code 2.1.133–2.1.146; track SchemaStore PR #5706 (PR #52).** Resurveyed the upstream CHANGELOG and the SchemaStore catalog after a 9-day gap. The original gating PR #5665 (sync to v2.1.138) was closed 2026-05-19 with comment "Superseded by #5706 which syncs to v2.1.143" — net win for batching since #5706 also picks up `worktree.bgIsolation`, `subagentStatusLine`, `statusLine.hideVimModeIndicator`, `sandbox.failIfUnavailable`, five env vars (`ANTHROPIC_WORKSPACE_ID`, `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE`, `CLAUDE_CODE_PLUGIN_PREFER_HTTPS`, `CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY`, `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`), and the hook `args: string[]` + `continueOnBlock` keys move out of the "future sync" bucket and into the same merge gate. Eleven configurator-territory keys total in #5706; live-verified against the PR's head-branch schema 2026-05-21. Two later items remain held for a future sync PR (hook output `terminalSequence` from 2.1.141; Stop/SubagentStop input `background_tasks` + `session_crons` from 2.1.145). **No template changes; no `tested_up_to` bump yet** — deferred to the post-#5706 unblock batch per the "no lone tracking bumps" rule. `CLAUDE_CODE_COMPAT` rationale comment refreshed to capture the resurvey window. Also: `/simplify` was renamed to `/code-review` in 2.1.146 — configurator ships `/review` (slash command) + `code-reviewer` (agent name), so no collision.

## [2.4.0] — 2026-05-12

Bundle release: scaffold-vs-git bootstrap hygiene driven by a brainstorming-phase dogfood (PRs #44 + #45 + #46 + #47), token-efficiency template fix (PR #43), `.claude-config.json` gitignore default (PR #41), tested-up-to bump (PR #40), `settings.local.json.example` MCP-token hint (PR #42), and a README accuracy pass (PR #39). All nine PRs were either driven by or surfaced by dogfooding `cc-configure` on existing/in-flight projects.

### v2.4.0 — scaffold-vs-git bootstrap hygiene

**Bootstrap dogfood — `cc-configure` on a project still in the brainstorming/planning phase surfaced four gaps:**

*Symptom:* the configurator scaffolds `CLAUDE.md` + `.claude/` + `.mcp*.json` + a `.gitignore` block, but never tells Claude (or the human) what the scaffold-time contract is. After running `cc-configure`, the user `git init`'d, wrote a one-line `.gitignore` (losing the auto-appended `# --- Claude Code ---` block), committed only the planning spec, and left `.claude/` + `.claude-config.json` untracked — every signal in the configurator output had nothing to say about it. Plus the schema's `repo_url` default leaked `git@github.com:user/repo.git` into committed files, and the Stop hook ran `pnpm test` on every Stop in a directory with no `package.json`.

- **`repo_url` default no longer leaks a fake URL into `CLAUDE.md` (PR #44).** Form schema default flipped from the legacy literal `git@github.com:user/repo.git` to `""`. New `normalize_conditional_placeholders()` step stamps a `[TODO:]` placeholder when value is empty or matches the legacy literal (second arm auto-upgrades v2.3.x configs on re-run). `[ PLACEHOLDERS ]` and `[ NEXT STEPS ]` both fire on the field. Interactive `--quick` prompt at Q4 carries an inline format example since the bracketed default no longer does. New `test/repo-url-placeholder/` fixtures cover empty default → `[TODO:]`, legacy literal upgrade, and real-URL passthrough.
- **Stop hook skips silently when the stack manifest hasn't landed yet (PR #45).** `stop-run-checks.sh` already skipped when the first binary wasn't on PATH; it did *not* skip when the binary existed but the project hadn't been scaffolded — so `cmd_test = "pnpm test"` with no `package.json` reported `FAIL (exit 1)` to the next turn every Stop. New `manifest_for()` helper maps the first binary to its stack's manifest (`package.json` for pnpm/npm/yarn/bun, `pyproject.toml` for uv/poetry/pip, `Cargo.toml` for cargo, `go.mod` for go, `Gemfile` for bundle/gem, `pom.xml` for mvn, `build.gradle` for gradle). Tools not in the map (tsc, pytest, ruff, eslint, prettier, …) have no guard and run unchanged. POSIX `case` keeps it macOS bash 3.2-portable. New `test/stop-run-checks/` fixture exercises both arms via a fake `pnpm` + marker file (jq-independent so it runs on any box).
- **CLAUDE.md ships `### Repo bootstrap` guidance + `[ NEXT STEPS ]` nudges a missing `git init` (PR #46).** `templates/core/CLAUDE.md` gains a `### Repo bootstrap` subsection under `## HOW > ### Git workflow` codifying what to commit (`CLAUDE.md`, `.claude/`, `.mcp*.json`, `claude-ctx`, source) vs. gitignore-by-default (`settings.local.json`, `.claude/logs/`, transient state, `.claude-config.json`), the rule "preserve the Claude Code .gitignore block if you rewrite `.gitignore` (or rerun `cc-configure --retrofit`)," and a nested-clone note. `configure.py`'s `[ NEXT STEPS ]` builder gains a fourth trigger — when the target dir lacks `.git/`, render a one-line nudge with the bootstrap incantation (`git init -b main && git add . && git commit -m '...'`). Suppressed under `--dry-run`. New `test/repo-bootstrap/` fixtures cover both arms.
- **`/verify-setup` audits four new scaffold-vs-git bootstrap concerns (PR #47).** Adds checks **#8 Repo URL placeholder** (flags `[TODO:` or the legacy literal still in CLAUDE.md), **#9 Claude Code gitignore block** (checks for the `# --- Claude Code ---` sentinel; suggests `cc-configure --retrofit` if missing), **#10 Nested `.git/` discipline** (`find -maxdepth 4 -name .git` then confirms each parent is in `.gitignore`), **#11 Scaffold committed** (only runs when a repo exists at root; `git ls-files --error-unmatch CLAUDE.md .claude/settings.json`). Frontmatter `allowed-tools` gains `Bash(find:*) Bash(git:*)`. Sample output + `Suggested next actions` block updated. New `test/verify-setup/test-bootstrap-checks-present.sh` pins the four headers and the two new tool entries.

**Other dogfood-driven fixes:**

- **`.claude-config.json` now gitignored by default (PR #41).** Added to `templates/core/.gitignore.append`. Surfaced by dogfooding `cc-configure` on an existing project: `/verify-setup` check #6 already flagged `.claude-config.json` as a working-state file that clutters diffs when tracked. Now matches the skill's recommendation out of the box; inline comment notes that teams who want to share configurator selections can remove the line.
- **`token-efficiency` pro-tier rules folded into `CLAUDE.md`, dropping the `paths: ["**"]` antipattern (PR #43).** The pro-tier `templates/token-efficiency/pro/_efficiency-core.md` shipped with `paths: ["**"]` (always-loaded) — exactly the shape `/verify-setup` check #2 tells users not to keep. Prose body (Reading files / Running bash / Reset rhythm / Planning / Subagents / Inline bash in skills) folds into the existing `## Token efficiency rules` section of `CLAUDE.md` under H3 subheads; standalone rule file is gone. Two persona snapshots (`solo-experienced`, `small-team`) lose the file. New `test/efficiency-placeholder/` fixtures cover both tier paths. **Retrofit note:** users re-running `cc-configure` over an existing v2 install with `tier=pro` keep the stale rule file on disk; `/verify-setup` continues to flag it.

**Docs / compat:**

- **README accuracy / completeness pass (PR #39).** Modules table rewritten to the post-v1.6.0 11-module reality (drops stale `commands-core` / `agents` / `token-efficiency-pro` / `lockdown` rows; adds `recommend-plugins`; surfaces `commands.subset`, `token-efficiency.tier`, and the four `safety.slop_scan*` flags inline). Personas table corrected to current `commands (rigorous|full)` values. Flags reference adds `--detailed` + `--persona`, marks `--preset` deprecated. Preflight count "four → five non-blocking checks." Quick-mode field count 50 → 55. Aggressive-preset effort-stamping list adds `/verify-setup`. README only — no code or template changes.
- **Bumped `CLAUDE_CODE_COMPAT.tested_up_to` from `2.1.128` → `2.1.132` (PR #40).** Four CC releases came out (2.1.129–2.1.132); one configurator-territory addition held pending schemastore (`skillOverrides`). No new hook events or MCP/agent/skill frontmatter fields in configurator territory. Users on 2.1.129–132 no longer see the "newer than tested range" `[ VERSION WARNINGS ]` block.
- **`settings.local.json.example` hints at MCP-token durability (PR #42).** Adds a `// env` comment-key in `templates/core/dot-claude/settings.local.json.example` documenting that the `env` block is the durable home for MCP auth tokens (`SONATYPE_TOKEN`, `GITHUB_TOKEN`). `[ ENV WARNINGS ]` preflight already caught absent tokens, but users had no signpost to a durable location. Pure docs / example change.

**Claude Code compat:** unchanged (2.1.116–2.1.132).

## [2.3.0] — 2026-05-06

Bundle release: v1-config upgrade-path bug fix (PR #36) + v1-upgrade UX polish (PR #37) + README attribution housekeeping for gstack-derived patterns (PR #38).

### v2.3.0 — v1-upgrade hardening + attribution housekeeping

**Bug fix — `load_config` legacy translate (PR #36):**
- `load_config` now applies `translate_legacy_modules` to a saved config's `selected` + `module_flags`, mirroring the `--modules` CLI path. Previously a v1 `.claude-config.json` carrying `lockdown` / `token-efficiency-pro` / `commands-core` / `agents` survived through every non-interactive path (`--yes`, `--save-config-only`, `--config`) untranslated.
- Resulting deprecations land in `initial["_deprecations"]` so the existing `[ DEPRECATED ]` render pipeline surfaces them uniformly.
- New `test/v1-legacy-upgrade/test-translate.sh` covers all four `LEGACY_MODULE_MAP` entries via `--save-config-only` roundtrip; wired into CI as `v1 legacy-config upgrade tests`.

**v1-upgrade UX polish (PR #37) — eight fixes surfaced by dogfooding `cc-configure` on a real v1 install:**

*Persona-flow bug fixes:*
- **No more double persona prompt on v1 upgrade.** The `[ NOTICE ]` branch prompted, then `quick_interactive` Q1 prompted again. New `skip_persona_q` kwarg threaded from `main`.
- **Persona overrides surfaced.** `detect_persona_overrides()` compares pre-persona `module_flags` against the persona's picks; `[ APPLIED ]` now shows `<module>.<key>: before → after` lines so silent overrides (e.g. `safety.lockdown: True → False`) become visible.

*Inference:*
- **Persona default on v1 NOTICE is now inferred.** `infer_persona()` scores each persona against the user's translated config (Jaccard module-set 0.7 + flag-match ratio 0.3, threshold 0.5) and suggests the closest fit. Idiosyncratic shapes fall back to `custom`.

*Output polish:*
- `wrote / backed-up / saved-config` lines no longer interleave; the retrofit report path joins the `wrote` group.
- `.gitignore` line lists patterns inline (`append 5 rules (.venv, __pycache__, …)`).
- 3 MCP profile alternates render as a single grouped `wrote 3 MCP profile alternates (…) — switch via cp` line.

*Retrofit report:*
- `Skipped` is split into **identical to v2 (safe to drop)** vs **differs from v2 (review)** by content-hash comparison. Each gets its own table + actionable recommendation.
- Stale `/retrofit Tier 3 future` footer replaced with a pointer to the shipped `/retrofit` skill.

5 new fixtures under `test/v1-upgrade-ux/` wired into CI as `v1 upgrade UX tests` (no-double-persona, override-visibility, inference, output-polish, retrofit-report).

**README attribution (PR #38):**
- **`README.md` `## Acknowledgments`** — adds a second paragraph crediting the MIT-licensed [garrytan/gstack](https://github.com/garrytan/gstack) (© 2026 Garry Tan) with four bullets covering the surfaces it informed: the four `_patterns/` blocks + `/investigate` + `/plan-eng-review`, the four discipline microbits + enforcer, the `security-auditor` agent grafts, and the `slop-scan` PostToolUse hook. Notes that no gstack files are vendored and that the configurator translates the patterns into its own voice. Restores symmetry with how `PacktPublishing/Agentic-Coding-with-Claude-Code` is credited above.

**Claude Code compat:** unchanged (2.1.116–2.1.128).

## [2.2.1] — 2026-05-05 — cosmetic carries cleanup

Closes 3 small items flagged during the v2.0.0 PR 4 code review:

- **`configure.py` docstring example** updated from the legacy `--modules core,safety,git-workflow,token-efficiency-pro,commands-core` to the v2 vocabulary (`token-efficiency`, `commands`); leads with quick mode + `--persona` examples.
- **Inline comment** near `resolve_dependencies` no longer references the removed `commands-core -> agents` mapping (those modules were folded in v1.6.0).
- **`--modules agents` deprecation message** no longer renders trailing empty parens. Was: `--modules agents → --modules commands ()`. Now: `--modules agents → --modules commands`. Other legacy translations with non-empty flags (`lockdown`, `token-efficiency-pro`, `commands-core`) keep their `(k=v)` suffix unchanged.

No behavior change beyond the cosmetic deprecation-message fix.

**Claude Code compat:** unchanged (2.1.116–2.1.128).


## [2.2.0] — 2026-05-05

Bundle release: skill extensions (PR 7) + slop-scan hook (PR 8).

### v2.2.0 — extensions to /review, /session-retro, security-auditor

**Skill grafts (this PR):**
- **`/review`** — embeds confidence gate (≥7), independent verification, and AI-slop detection. New output sections: `[ AUTO-FIXED ]` (apply obvious low-risk fixes inline), `[ ASK ]` (ambiguous calls requiring user input), `[ SLOP ]` (AI-slop checklist over the diff), `[ COMPLETENESS ]` (verify each PR/commit requirement is implemented). Defers bug fixes to `/investigate` per the Iron Law.
- **`/session-retro`** — keeps existing doc-update flow; adds a structured `Hypothesis / Setup / Result / Conclusion / Follow-ups` doc written to `.claude/retros/<date>.md`. Format matches the existing `experiments-memory` module's schema. Slop-reflection prompt at end surfaces drift patterns over time.
- **`security-auditor` agent** — embeds confidence gate (≥8, stricter than rigor default), independent verification, 17 false-positive exclusions distilled from gstack `/cso`, a concrete-exploit requirement (every finding must include a one-paragraph exploit scenario), and a lightweight STRIDE checklist. Sonatype MCP wiring preserved.
- **`run_check`** validates pattern-include lines in `/review` and the `security-auditor` agent (in addition to `/investigate` and `/plan-eng-review` from v2.1.0).

**Slop-scan + safety sub-flags (PR 8):**
- New `safety/hooks/slop-scan.sh` PostToolUse hook on Write/Edit/NotebookEdit. 4 default pattern categories (filler / marketing-voice / hedging / em-dash-spam) — high confidence, low FP rate.
- 4 new safety sub-flags: `slop_scan` (default false; non-custom personas opt in), `slop_scan_action` (warn|block, default warn), `slop_scan_density` (opt-in, FP-prone), `slop_scan_imports` (opt-in, FP-prone).
- New **`extraSettingsEnv`** mechanism: a flag's selected value (or the `$VALUE` sentinel) is merged into `settings.env`, exposing per-flag config to the running hook.
- 4 non-custom personas pre-set `slop_scan=true` + `slop_scan_action=warn`. `custom` leaves it false.
- 6 bash fixture tests (`test/slop-scan/`) verify clean / filler / marketing / hedging / em-dash / block-mode. CI runs all 6.

**Claude Code compat:** unchanged (2.1.116–2.1.128).

## [2.1.0] — 2026-05-05

Bundle release: rigor skills (PR 5) + microbits (PR 6).

### v2.1.0 — rigor skills (cross-cutting patterns + /investigate + /plan-eng-review)

**New:**
- `templates/commands/_patterns/` directory with 4 reusable cross-cutting blocks:
  - `confidence-gate.md` — internal 1-10 rating; surface only ≥7 (rigor) / ≥8 (security)
  - `independent-verification.md` — re-check from a different angle before reporting
  - `no-fix-without-investigation.md` — Iron Law: hypothesis → trace → findings before any code change
  - `ai-slop-detection.md` — filler / marketing / hedging / em-dash patterns to flag
- `/investigate` skill — systematic root-cause debugging; embeds Iron Law + confidence gate + independent verification. Writes findings doc to `.claude/investigations/<topic>-<date>.md` before any proposed fix.
- `/plan-eng-review` skill — engineering review of plans before implementation. Surfaces hidden assumptions, requires data-flow diagram + state machines + test matrix + failure modes + edge cases.
- New `rigorous` value for `commands.subset` flag (linear ordering: `curated ⊂ full ⊂ rigorous`). Rigorous = full + /investigate + /plan-eng-review.
- `run_check` now validates that rigor skills embed their required `_patterns/*.md` includes. Catches drift.

**Persona pre-pick changes (Spec #2 Amendment B):**
- `solo-experienced`: `full` → `rigorous` (gets /investigate + /plan-eng-review)
- `small-team`: `full` → `rigorous`
- `library-author`: `curated` → `full` (gets all 9 commands + 4 agents; no rigor)
- `solo-newer` + `custom`: unchanged

**Microbits + enforcer hook (PR 6):**
- `/freeze` / `/unfreeze` — pause work, blocks all Write/Edit/NotebookEdit until unfrozen.
- `/guard <glob>` — protect specific paths from edits (rejects matching writes).
- `/careful <glob>` — heightened-caution mode (emits an `ask` action so Claude Code prompts the user before each matching write).
- `microbit-enforcer.sh` PreToolUse hook auto-installed alongside the microbits when `commands.subset` is `full` or `rigorous`. Single bash hook handles all 3 marker files (`.claude/.frozen`, `.claude/.guarded`, `.claude/.careful`).
- `SessionStart` hook clears all 3 markers — session-scoped lifecycle.
- 4 bash fixture tests (`test/microbit-enforcer/`) verify clean pass-through, frozen block, guarded block + non-match pass, and careful ask-action emission. CI runs all 4.

**Claude Code compat:** unchanged (2.1.116–2.1.128).

## [2.0.0] — 2026-05-05

Bundle release: v1.6.0 module consolidation + v1.7.0 persona engine + v2.0.0 quick-flow intake. Four PRs (#27, #28, #29, #30).

### v2.0.0 — quick-flow intake + placeholders

**Breaking UX change (config files unchanged):**
- `cc-configure` (no flags) now opens **5-question quick mode** instead of the full 50-field intake. Asks: persona, project name, stack preset, repo URL, license. Persona drives module/flag/form-value defaults.
- Use `--detailed` to reach the v1 50-field interactive intake.

**New:**
- `quick_interactive` + `_ask_persona` helpers in `configure.py`.
- `inject_placeholders` + `PLACEHOLDER_TEMPLATES` for `[TODO: ...]` defaults in newer-coder documentation fields (goals, non-goals, common-instructions, known-gotchas).
- `[ PLACEHOLDERS ]` report block lists every `[TODO:]` field by name (greppable + idempotent).
- `[ NEXT STEPS ]` report block surfaces tailored tips: edit placeholders, upgrade persona kit, migrate off legacy flags. Empty (block suppressed) when no tips apply.
- One-time `[ NOTICE ]` persona prompt for v1 configs (`schema_version<2`). Bypassed by every non-interactive path (`--yes`, `--persona`, `--detailed`, `--config`, `--modules`, `--save-config-only`). Picking `custom` preserves v1 behavior indefinitely.
- `examples/v1-legacy-config/.claude-config.json` fixture for back-compat regression coverage.

**Back-compat preserved:**
- v1 `.claude-config.json` files load and round-trip without edits.
- `--yes` against any v1 config is identical to v1.x behavior (treated as `persona: custom`).
- `--preset balanced|aggressive|relaxed` continues to work (now emits a `[ DEPRECATED ]` line — slated for removal in v3.0).
- `--modules <legacy-name>` still works for `lockdown`, `token-efficiency-pro`, `commands-core`, `agents` (each emits a `[ DEPRECATED ]` translation line).

**Known follow-up:** the `pointers` form field is in `FORM_SCHEMA` but not interpolated by the current core `CLAUDE.md` template. Removed from `solo-newer.use_placeholders_for` to avoid invisible-placeholder UX. Re-add if the template grows a `## Where to look` / `## Pointers` section that consumes it.

**Claude Code compat:** unchanged (2.1.116–2.1.128).

### v1.7.0 — persona engine

**New:**
- `PERSONAS` constant in `config_schema.py` with 5 entries: `solo-newer`, `solo-experienced`, `small-team`, `library-author`, `custom`. Each entry pre-picks modules + module_flags + form-value defaults.
- `pick_persona_modules(persona)` and `apply_persona_defaults(persona, form_values)` helpers in `configure.py`.
- `--persona <name>` CLI flag (combine with `--yes` for fully non-interactive scaffolding). Persona pre-picks run first so explicit `--modules` / `--preset` can override.
- `[ APPLIED ]` report block shows persona + final module list with active flag values inline (e.g. `commands (subset=full)`).
- `run_check` now validates that PERSONAS reference real module IDs.
- 5 persona snapshot fixtures under `examples/persona-*/` with CI diff step. Each captures the file-tree manifest a fresh `--persona <name> --yes` produces. CI fails on drift; regenerate intentionally by re-running the loop.

**v1 behavior preserved:**
- `--yes` against any v1 `.claude-config.json` (no `persona` field) still works identically — treated as `persona: custom` ≡ explicit-field flow.

Quick-flow intake (5 questions as default no-flag invocation, `[TODO:]` placeholders, one-time persona prompt for v1 configs) lands in v2.0.0.

**Claude Code compat:** unchanged (2.1.116–2.1.128).

### v1.6.0 — module consolidation

**Modules consolidated (back-compat preserved):**
- `lockdown` → `safety` module + `safety.lockdown` sub-flag.
- `token-efficiency-pro` → `token-efficiency` module + `tier=pro` flag.
- `commands-core` + `agents` → `commands` module + `subset` flag (`curated` | `full`, default `full`).

**Legacy `--modules` names** (`lockdown`, `token-efficiency-pro`, `commands-core`, `agents`) and `--preset balanced|aggressive|relaxed` continue to work; each emits a line in a new `[ DEPRECATED ]` block. Slated for removal in v3.0.

**Schema:** `.claude-config.json` gains optional `persona`, `module_flags`, `schema_version` fields (all back-compat; absent ≡ v1 behavior). Lays groundwork for the persona engine landing in v2.0.0.

**New mechanisms (used by the consolidated modules):**
- `flags` schema on a MODULES entry: per-flag `default`, `description`, `extraSettingsPatch` (string OR dict keyed by selected value), `extraPaths` (dict keyed by selected value), `filterPaths` (allowlist that subsets `m["paths"]`).
- `LEGACY_MODULE_MAP` + `translate_legacy_modules` helper for legacy-name back-compat.
- `[ DEPRECATED ]` report block following the existing preflight `check_X()` pattern.
- `run_check` now validates the flags schema (missing `default`/`description`, dangling `extraSettingsPatch`/`extraPaths`/`filterPaths` references).

User-facing module count drops from 13 → 11. Visible `--modules` vocabulary still accepts old names.

**Claude Code compat:** unchanged (2.1.116–2.1.128).

### Changed
- **Bumped `CLAUDE_CODE_COMPAT.tested_up_to` from `2.1.121` → `2.1.128`.** Five CC releases came out (2.1.122, 2.1.123, 2.1.126, 2.1.128 — 2.1.124/125/127 were not published). Changelog review found no new `settings.json` keys, hook events, or MCP/agent/skill frontmatter fields in configurator territory. Notable items: 2.1.122 defensive parse (malformed `hooks` entries no longer invalidate the whole settings file, same theme as 2.1.121's enum-validation fix); 2.1.128 reserved the MCP server name `workspace` (verified clean — no configurator template uses that name); 2.1.128 added `channelsEnabled` for managed/enterprise settings (out of scope); 2.1.126 expanded `--dangerously-skip-permissions` scope to cover writes under `.claude/`, `.git/`, `.vscode/`, and shell config files (catastrophic-removal commands still prompt). No template changes required. Users on 2.1.122–128 no longer see the "newer than tested range" `[ VERSION WARNINGS ]` block. README Requirements line updated to match.

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
