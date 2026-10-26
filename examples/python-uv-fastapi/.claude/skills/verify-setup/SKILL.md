---
name: verify-setup
description: Audit the current .claude/ configuration against best practices — CLAUDE.md size, rule-file scoping, MCP overhead, schema URL drift, orphan local settings, scaffold-vs-git bootstrap hygiene. Complement to /check-context (which covers token cost); this covers the shape of the setup itself.
effort: minimal
allowed-tools: Read Grep Glob Bash(wc:*) Bash(jq:*) Bash(test:*) Bash(cat:*) Bash(grep:*) Bash(find:*) Bash(git:*)
---

# Verify the Claude Code setup

Audit the current project's `.claude/` directory. Produce a checklist report. Do **not** write fixes without asking — surface findings and let the user decide.

## Checks

### 1. CLAUDE.md size
- Read `CLAUDE.md` (repo root). Count lines.
- `≤ 200` → ✓ within soft cap
- `201–300` → ⚠ over soft cap; recommend moving path-specific content to `.claude/rules/*.md`
- `> 300` → ✗ significantly bloated; suggest specific section candidates to split off

### 2. Path-scoped rules
- `ls .claude/rules/*.md` (if directory exists).
- Each file: verify it has `paths:` frontmatter. A rule without `paths:` is always-loaded — defeating the point of the folder.
- Flag any rule whose `paths:` is `"**"` (matches everything) — should be in `CLAUDE.md` instead.
- If `.claude/rules/` is empty but `CLAUDE.md > 150 lines`, recommend introducing path-scoped rules.

### 3. Settings schema URL
- Read `.claude/settings.json`. Parse as JSON.
- `$schema` must equal `https://json.schemastore.org/claude-code-settings.json`.
- Any other value or a missing schema key → ✗ (Claude Code will reject the file silently and drop all settings).
- Also: if the file doesn't parse as valid JSON → ✗ fatal (settings ignored entirely).

### 4. MCP overhead + drift

**Count check (always runs):**
- If `.mcp.json` exists, count entries under `mcpServers` that aren't `//`-prefixed.
- `0–1` → ✓ | `2–3` → info | `4+` → ⚠ (recommend per-task profiles via `./claude-ctx`).
- Also report whether per-task `.mcp.<profile>.json` files exist.

**Drift check (runs only if `.claude/.cc-manifest.json` exists):**
- Parse `manifest_version`. If ≠ `1` → `[ - ] Drift: manifest v{N}, this skill is v1; skipping drift narrative` and fall back to count-only.
- Compute `added = current ∖ baseline` and `removed = baseline ∖ current`.
- Both empty → `[ ✓ ] Drift: 0 changes since baseline ({written_at}).`
- Otherwise → `[ ⚠ ] Drift: {N} changes since baseline ({written_at}).` Then for each added server, emit a sub-block (see below). For each removed server, one sub-bullet (name only — removals don't undermine efficiency).

**For each ADDED server, the sub-block must cover:**

1. **What it is** — name + inferred purpose from `command + args`. State "unknown" if the model can't identify it.
2. **Cost class** — qualitative session-start token + latency impact.
3. **Supply-chain nudge** — parse the package coordinate:
   - `npx [-y] <pkg>[@<ver>]` → npm package
   - `uvx <pkg>[@<ver>]` → PyPI package
   - `node /local/...` / non-registry → skip
   - For registry-resolvable packages, **recommend the user invoke the available Sonatype MCP tools (`getComponentVersion`, `getLatestComponentVersion`, `getRecommendedComponentVersions`) to vet vulnerability status and pin recommendations before keeping the server.** Especially flag `@latest` / unpinned versions.
4. **Profile fit** — if task-specific (build tool, UI-only, research-only), recommend `.mcp.<profile>.json` rather than keeping in always-loaded `.mcp.json`.

**Plan-of-attack summary (when drift exists):**

- Accept new baseline: `cc-configure --retrofit`
- Revert: edit `.mcp.json` to remove added entries
- Always vet new servers with Sonatype before accepting.

**Edge cases:**

- No manifest + no `.mcp.json` → `[ - ] Drift: no baseline, no MCPs`.
- Manifest present + no `.mcp.json` → report removals only.
- No manifest + `.mcp.json` present → `[ ⚠ ] Drift: no baseline recorded (project predates drift monitor) — run cc-configure --retrofit to establish baseline.`

### 4b. Stack drift

**Runs only if** `manifest_version ≥ 2` and `stack_manifests` field is present in the manifest.

- Parse `stack_manifests` → baseline set.
- Probe repo root for the 7 known filenames (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `pom.xml`, `build.gradle`) → current set.
- Both equal → `[ ✓ ] Stack drift: 0 changes since baseline ({written_at}).`
- Otherwise → `[ ⚠ ] Stack drift: {N} changes since baseline.` Then per-change narrative:
  - `+ pyproject.toml` → "Python added. cc-configure baseline was Node-only; re-run cc-configure to pick up Python-specific patterns (uv detection, pytest defaults, ruff config)."
  - `+ Cargo.toml` → "Rust added. Re-run cc-configure to pick up Rust-specific patterns (cargo check, clippy)."
  - `+ go.mod` → "Go added. Re-run cc-configure for Go-specific patterns (go vet, golangci-lint)."
  - `- package.json` → "Node removed. Stop-hook checks that reference pnpm/npm/yarn will now skip silently — re-run cc-configure to reset for the new stack."
  - Apply the same shape for the other known manifests.

**Plan of attack when drift exists:**

- Accept new baseline: `cc-configure --retrofit`
- Revert: restore the missing manifest, or remove the unwanted one.

### 4c. Command alignment

**Runs only if** `check_commands` field is present in the manifest (i.e., v2+ manifest).

- For each `{kind: binary}` entry, look up the expected manifest via the same `manifest_for()` table that `stop-run-checks.sh` uses (pnpm/npm/yarn/bun → `package.json`, uv/poetry/pip → `pyproject.toml`, cargo → `Cargo.toml`, go → `go.mod`, bundle/gem → `Gemfile`, mvn → `pom.xml`, gradle → `build.gradle`). Binaries outside this map (tsc, pytest, ruff, eslint, …) have no guard and are skipped silently.
- **Pre-bootstrap skip:** If the expected manifest was not in the baseline `stack_manifests` either, skip — the project hasn't bootstrapped its stack yet (typical right after `cc-configure` on an empty dir), so the configured command isn't drift, just pre-bootstrap. Same spirit as `stop-run-checks.sh`'s manifest-missing rule.
- All commands have backing → `[ ✓ ] Command alignment: configured tools match current stack.`
- Mismatches → `[ ⚠ ] Command alignment: {N} configured checks have no stack backing.` Per mismatch list: `{kind}: {binary} needs {expected manifest}, but it's not present.` Suggest a replacement based on whichever stack manifest IS present (e.g., if `pyproject.toml` is present and `pnpm test` was configured, suggest `uv run pytest` / `pytest`).

**Plan of attack:** re-run cc-configure to pick stack-appropriate commands, or edit `.claude-config.json` and re-run `cc-configure --retrofit`.

### 5. Hook weight
- Read `.claude/settings.json`, walk `hooks.PreToolUse`, `hooks.PostToolUse`, `hooks.PostToolUseFailure`.
- Flag any command whose first token (basename) is `uv`, `python`, `python3`, `node`, `poetry`, `npm`, `npx`, `pnpm`, `bun`, `deno`, `ruby`, `java`, or `go`. Heavy interpreters on per-tool events add hundreds of ms per call.

### 6. Local settings discipline
- If `.claude/settings.local.json` exists, confirm it's covered by `.gitignore`.
- Check for `.claude-config.json` at repo root; if present and tracked by git, warn (it's a working-state file, safe to commit but clutters diffs).

### 7. Orphan primitives
- `.claude/agents/*.md` referenced in any shipped skill's `agent:` frontmatter but not present → flag as broken reference (e.g., a skill says `agent: code-reviewer` but no `code-reviewer.md` exists).
- `.claude/skills/*/SKILL.md` without `name:` or `description:` frontmatter → invalid.

### 8. Repo URL placeholder
- Read `CLAUDE.md`. Find the `**Repo:**` line.
- Value starts with `[TODO:` → ⚠ (cc-configure stamped a placeholder; user never filled it in).
- Value equals the legacy literal `git@github.com:user/repo.git` → ⚠ (stale default from a pre-v2.4 install — re-run `cc-configure` or edit the line).
- Anything else, or the line is absent → ✓.

### 9. Claude Code gitignore block
- Read `.gitignore` at repo root.
- The sentinel `# --- Claude Code ---` must be present. cc-configure appends a block of transient/local-only paths under that header; without it, `settings.local.json`, `.claude/logs/`, transient state files, and `.claude-config.json` can leak into commits.
- Missing sentinel → ⚠ (recommend `cc-configure --retrofit` to re-append, or restore manually from `templates/core/.gitignore.append`).
- `.gitignore` doesn't exist → ⚠ for the same reason.

### 10. Nested `.git/` discipline
- `find . -mindepth 2 -maxdepth 4 -type d -name .git` to locate vendored / wrapper / cloned-upstream repos inside this project.
- For each match: its parent directory must appear in `.gitignore`. An unignored nested `.git/` confuses the outer repo (`git status` treats it as a submodule or untracked tree).
- Any unignored nested repo → ⚠ with the path; suggest adding the parent dir to `.gitignore` above the `# --- Claude Code ---` block.
- None present → `[ - ]` skipped.

### 11. Scaffold committed
- Only if `.git/` exists at repo root (else `[ - ]` skipped — covered by `[ NEXT STEPS ]` at scaffold time).
- `git ls-files --error-unmatch CLAUDE.md .claude/settings.json` — both files must be tracked.
- Either missing from the index → ⚠ (the configurator output was generated but never committed; collaborators will not see it).
- Tracked → ✓.

### 12. Discipline-skills duplication

- Skip unless `.claude/skills/_LICENSE-discipline-skills.md` exists (the configurator's `discipline-skills` module is installed).
- Check the user's installed plugins via glob (any marketplace): `ls -d ~/.claude/plugins/cache/*/superpowers 2>/dev/null` (a directory match under any marketplace name — `claude-plugins-official`, `obra-superpowers-marketplace`, or other — means the upstream plugin is installed).
- **Neither installed (discipline-skills marker absent):** `[ - ] Discipline skills: module not installed` (skipped — nothing to compare).
- **Only the configurator's module:** `[ ✓ ] Discipline skills: configurator's curated 7 (no upstream overlap).`
- **Only upstream superpowers:** `[ - ] Discipline skills: upstream superpowers plugin in use (configurator's module not installed).`
- **Both installed:** `[ ⚠ ] Discipline skills: BOTH installed — your /skills menu has 7 forked skills + 14 upstream skills with the same names. The configurator's SessionStart bootstrap auto-suppresses, but skill invocations may resolve to either copy depending on namespace.` Suggest: pick one — either `cc-configure --retrofit` without `discipline-skills` to drop the fork, or `/plugin uninstall superpowers` to drop the upstream.

### 13. Superseded `/review` skill

- Skip unless BOTH `.claude/skills/review/SKILL.md` and `.claude/skills/review-branch/SKILL.md` exist.
- Configurator releases before this rename shipped the skill as `review`. Claude Code 2.1.223 made `/review` the alias of the bundled `/code-review`, and a project skill of that name wins it — so the leftover directory hides Claude Code's multi-agent reviewer. The configurator has no mechanism to delete a file it previously wrote, so an upgraded project keeps both.
- **Both present:** `[ ⚠ ] Superseded skill: .claude/skills/review/ is left over from an older scaffold and shadows the bundled /review (alias of /code-review). The replacement is .claude/skills/review-branch/. Delete the old directory: rm -rf .claude/skills/review`
- **Only `review-branch/`:** `[ ✓ ] Skills: no superseded /review shadow.`
- Neither, or only `review/` (project predates the rename and hasn't been re-scaffolded) → `[ - ]` skipped.

### 14. Starting mode pinned

- Read `.claude/settings.json` → `permissions.defaultMode`.
- Since Claude Code 2.1.283/2.1.284 a session with no configured mode starts in auto mode, which routes edits through `sed` and heredocs — the scaffold's Write/Edit hooks (secret scan, formatter, slop scan, microbit enforcer) never see those edits. The safety module's discipline profile writes `"default"` here.
- `default`, `acceptEdits` or `plan` → `[ ✓ ] Starting mode: <value> (pinned in .claude/settings.json)`.
- `auto` or `bypassPermissions` → `[ ✗ ] Starting mode: <value> is ignored from project and local settings (since 2.1.257) — sessions start in Claude Code's built-in default instead; set it in ~/.claude/settings.json or use default / acceptEdits / plan here.`
- Absent → `[ ⚠ ] Starting mode: none pinned — sessions start in auto mode on Claude Code ≥ 2.1.284; re-run cc-configure (safety.discipline) or add permissions.defaultMode: "default".`
- Always append one line when the value is pinned: VS Code sessions do not read a project's starting mode; they use `claudeCode.initialPermissionMode` (VS Code user settings) or `~/.claude/settings.json`.

### 15. Discipline env vars

- Skip (`[ - ]`) unless the safety module is installed (`.claude/hooks/block-dangerous-bash.sh` exists) and `.claude-config.json` does not set `module_flags.safety.discipline` to `false`.
- Read `.claude/settings.json` → `env`. Expect `CLAUDE_CODE_FORK_SUBAGENT` = `"0"` (fork mode off, so Claude can wait for `code-reviewer` inside the turn) and `CLAUDE_CODE_ENABLE_TODO_TOOLS` = `"1"` (task-tracking tools back on the 5-generation models).
- Both present → `[ ✓ ] Discipline env: fork mode off, task tools on`.
- Either missing → `[ ⚠ ] Discipline env: <name> missing from settings.env → re-run cc-configure, or add it by hand`. Project-scope `env` has been losing keys in 2026 (`TMPDIR`, `OTEL_*`, `CLAUDE_CODE_DISABLE_ATTACHMENTS`); if Claude Code's env-vars reference now says either of these is user/managed-only, say so and point at `~/.claude/settings.json`.

### 16. Account skill sync

- Since Claude Code 2.1.275, the skills and plugins enabled on the claude.ai account sync into terminal sessions signed in with it (`~/.claude/skills/synced/`). They share the per-turn skill listing, capped at 1% of the context window, and when it overflows Claude Code drops descriptions — the text project skills trigger on.
- `ls ~/.claude/skills/synced/` empty or absent → `[ ✓ ] Account skill sync: no account skills in the listing`.
- Non-empty, and `syncClaudeAiSkills: false` is set in `~/.claude/settings.json` or `.claude/settings.local.json` → `[ ✓ ] Account skill sync: off (N synced copies will be trashed at next start)`.
- Non-empty and sync still on → `[ ⚠ ] Account skill sync: N synced skills share the listing with this project's skills → set syncClaudeAiSkills: false (and syncClaudeAiPlugins: false) in ~/.claude/settings.json or .claude/settings.local.json`. Both keys are honored from user, local or managed scope only — never suggest the committed `.claude/settings.json`.

### 17. Machine lock (user scope)

- The project file pins the starting mode and the discipline env vars (checks 14–15). Three locks only a machine-level file can hold: the background updater, auto mode's reach through Shift+Tab, and the auto-mode classifier in plan mode. Read `~/.claude/settings.json` (`%USERPROFILE%\.claude\settings.json` on Windows) and report one line per lock. A managed settings file can carry the same keys; if `claude doctor` already reports auto-updates disabled, say where that comes from instead of warning.
- `env.DISABLE_AUTOUPDATER` = `"1"` (or `env.DISABLE_UPDATES` = `"1"`) → `[ ✓ ] Auto-updates: off (DISABLE_AUTOUPDATER in ~/.claude/settings.json)`. Otherwise → `[ ⚠ ] Auto-updates: on — a native install replaces Claude Code in the background, off the version the scaffold is designed for; add env.DISABLE_AUTOUPDATER: "1" to ~/.claude/settings.json and confirm with claude doctor`. The old `autoUpdates` key in `~/.claude.json` does not count: it is gone from the settings reference and does not stop a native install.
- `disableAutoMode` = `"disable"` (top level or under `permissions`) → `[ ✓ ] Auto mode: removed from the Shift+Tab cycle`. Otherwise → `[ ⚠ ] Auto mode: one Shift+Tab away — set disableAutoMode: "disable" in ~/.claude/settings.json (or discipline_strict in the project)`.
- `useAutoModeDuringPlan` = `false` → `[ ✓ ] Plan mode: prompts for shell commands`. Otherwise → `[ ⚠ ] Plan mode: the auto-mode classifier approves shell commands silently — set useAutoModeDuringPlan: false in ~/.claude/settings.json or .claude/settings.local.json`. Never suggest the committed `.claude/settings.json` for this key; it is honored from user, local or managed scope only.
- File absent → the three ⚠ lines, each starting `no ~/.claude/settings.json —`. The full setup, including the VS Code extension and the optional managed-settings ceiling, is docs/11 § Once per machine.

## Output format

```
PROJECT /absolute/path/here

[ ✓ ] CLAUDE.md: 130 lines (soft cap 200)
[ ⚠ ] Path-scoped rules: none found, CLAUDE.md is 180 lines → consider splitting frontend/backend/tests rules
[ ✓ ] Settings schema: https://json.schemastore.org/claude-code-settings.json
[ ⚠ ] MCP: 4 servers loaded globally — consider per-task profiles (./claude-ctx research, etc.)
[ ✓ ] Stack drift: 0 changes since baseline (2026-05-21T00:00:00Z)
[ ⚠ ] Command alignment: 1 configured check has no stack backing — test (pnpm needs package.json)
[ ✓ ] Hook weight: no heavy-interpreter hooks
[ ✓ ] Local settings: settings.local.json covered by .gitignore
[ ✓ ] Orphan primitives: none
[ ⚠ ] Repo URL: still the [TODO:] placeholder — fill in CLAUDE.md line 11
[ ⚠ ] Gitignore block: `# --- Claude Code ---` sentinel missing → run `cc-configure --retrofit`
[ - ] Nested .git/: none found
[ ⚠ ] Scaffold committed: .claude/settings.json untracked → `git add .claude/ && git commit`
[ - ] Discipline skills: module not installed
[ ✓ ] Starting mode: default (pinned in .claude/settings.json)
[ ✓ ] Discipline env: fork mode off, task tools on
[ ⚠ ] Account skill sync: 31 synced skills share the listing with this project's skills → set syncClaudeAiSkills: false in ~/.claude/settings.json
[ ✓ ] Auto-updates: off (DISABLE_AUTOUPDATER in ~/.claude/settings.json)
[ ⚠ ] Auto mode: one Shift+Tab away — set disableAutoMode: "disable" in ~/.claude/settings.json
[ ✓ ] Plan mode: prompts for shell commands

Suggested next actions:
1. Extract frontend-specific rules from CLAUDE.md (lines 45–78) into .claude/rules/frontend.md with paths: "src/frontend/**"
2. Create .mcp.research.json + .mcp.frontend.json profiles; use ./claude-ctx for scoped sessions.
3. Edit CLAUDE.md line 11 to replace [TODO:] with the real repo URL.
4. Restore the Claude Code .gitignore block (rerun cc-configure --retrofit, or append templates/core/.gitignore.append).
5. Stage and commit the configurator scaffold so collaborators see it.
6. Add disableAutoMode: "disable" to ~/.claude/settings.json (docs/11 § Once per machine).
```

Each row: `[ ✓ | ⚠ | ✗ ]`, the check name, the finding in one line.

## When to skip a check

- If a dir doesn't exist and the check is about its contents, report `[ - ]` (skipped) with a one-line reason.
- If a file is missing but the check is about its presence, report `[ ✗ ]` only if it's required (`.claude/settings.json`); else `[ - ]`.

Don't pad the report with commentary. Every line either reports a finding or proposes a concrete action. If everything is clean, say so in one sentence and stop.
