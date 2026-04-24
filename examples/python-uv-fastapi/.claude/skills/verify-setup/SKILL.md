---
name: verify-setup
description: Audit the current .claude/ configuration against best practices — CLAUDE.md size, rule-file scoping, MCP overhead, schema URL drift, orphan local settings. Complement to /check-context (which covers token cost); this covers the shape of the setup itself.
effort: minimal
allowed-tools: Read Grep Glob Bash(wc:*) Bash(jq:*) Bash(test:*) Bash(cat:*) Bash(grep:*)
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

### 4. MCP overhead
- If `.mcp.json` exists, count the entries under `mcpServers` that aren't keys starting with `//`.
- `0–1` servers → ✓
- `2–3` → info
- `4+` → ⚠ recommend per-task profiles via `./claude-ctx <profile>` (see `docs/mcp-servers.md`)
- Also report whether per-task `.mcp.<profile>.json` files exist.

### 5. Hook weight
- Read `.claude/settings.json`, walk `hooks.PreToolUse`, `hooks.PostToolUse`, `hooks.PostToolUseFailure`.
- Flag any command whose first token (basename) is `uv`, `python`, `python3`, `node`, `poetry`, `npm`, `npx`, `pnpm`, `bun`, `deno`, `ruby`, `java`, or `go`. Heavy interpreters on per-tool events add hundreds of ms per call.

### 6. Local settings discipline
- If `.claude/settings.local.json` exists, confirm it's covered by `.gitignore`.
- Check for `.claude-config.json` at repo root; if present and tracked by git, warn (it's a working-state file, safe to commit but clutters diffs).

### 7. Orphan primitives
- `.claude/agents/*.md` referenced in any shipped skill's `agent:` frontmatter but not present → flag as broken reference (e.g., a skill says `agent: code-reviewer` but no `code-reviewer.md` exists).
- `.claude/skills/*/SKILL.md` without `name:` or `description:` frontmatter → invalid.

## Output format

```
PROJECT /absolute/path/here

[ ✓ ] CLAUDE.md: 130 lines (soft cap 200)
[ ⚠ ] Path-scoped rules: none found, CLAUDE.md is 180 lines → consider splitting frontend/backend/tests rules
[ ✓ ] Settings schema: https://json.schemastore.org/claude-code-settings.json
[ ⚠ ] MCP: 4 servers loaded globally — consider per-task profiles (./claude-ctx research, etc.)
[ ✓ ] Hook weight: no heavy-interpreter hooks
[ ✓ ] Local settings: settings.local.json covered by .gitignore
[ ✓ ] Orphan primitives: none

Suggested next actions:
1. Extract frontend-specific rules from CLAUDE.md (lines 45–78) into .claude/rules/frontend.md with paths: "src/frontend/**"
2. Create .mcp.research.json + .mcp.frontend.json profiles; use ./claude-ctx for scoped sessions.
```

Each row: `[ ✓ | ⚠ | ✗ ]`, the check name, the finding in one line.

## When to skip a check

- If a dir doesn't exist and the check is about its contents, report `[ - ]` (skipped) with a one-line reason.
- If a file is missing but the check is about its presence, report `[ ✗ ]` only if it's required (`.claude/settings.json`); else `[ - ]`.

Don't pad the report with commentary. Every line either reports a finding or proposes a concrete action. If everything is clean, say so in one sentence and stop.
