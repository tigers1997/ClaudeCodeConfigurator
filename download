# Template library index

Every module produces one or more drop-in files for a new Claude Code project. The configurator (`configurator.html`) composes these into a selectable bundle. You can also copy files directly.

**Note on folder names in this library:** `dot-claude/` means `.claude/` in the target project. `mcp.json` in `mcp/` becomes `.mcp.json` at the project root. This is a workaround for the storage layer — the generated setup scripts handle the rename automatically.

## Core (always included)
- `core/CLAUDE.md` → `./CLAUDE.md`
- `core/dot-claude/settings.json` → `.claude/settings.json`
- `core/dot-claude/settings.local.json.example` → `.claude/settings.local.json.example`
- `core/.gitignore.append` → append to `./.gitignore`

## Safety & permissions
- `safety/hooks/block-dangerous-bash.sh` → `.claude/hooks/block-dangerous-bash.sh`
- `safety/hooks/scan-secrets.sh` → `.claude/hooks/scan-secrets.sh`
- `safety/settings-patch.json` → merge into `.claude/settings.json` under `hooks`

## Git workflow
- `git-workflow/hooks/format-on-write.sh` → `.claude/hooks/format-on-write.sh`
- `git-workflow/hooks/stop-run-checks.sh` → `.claude/hooks/stop-run-checks.sh`
- `git-workflow/settings-patch.json` → merge into `.claude/settings.json` under `hooks`

## Token efficiency
- `token-efficiency/dot-claude/rules/_scoping-guide.md` → `.claude/rules/_scoping-guide.md` (docs; safe to delete after reading)
- `token-efficiency/dot-claude/rules/frontend.md` → `.claude/rules/frontend.md`
- `token-efficiency/dot-claude/rules/backend.md` → `.claude/rules/backend.md`
- `token-efficiency/dot-claude/rules/tests.md` → `.claude/rules/tests.md`
- `token-efficiency/hooks/pre-compact-snapshot.sh` → `.claude/hooks/pre-compact-snapshot.sh`

## Slash commands (skills)
- `commands/plan/SKILL.md` → `.claude/skills/plan/SKILL.md`
- `commands/review/SKILL.md` → `.claude/skills/review/SKILL.md`
- `commands/commit/SKILL.md` → `.claude/skills/commit/SKILL.md`
- `commands/ship/SKILL.md` → `.claude/skills/ship/SKILL.md`
- `commands/sync-docs/SKILL.md` → `.claude/skills/sync-docs/SKILL.md`

## Subagents
- `agents/code-reviewer.md` → `.claude/agents/code-reviewer.md`
- `agents/test-runner.md` → `.claude/agents/test-runner.md`
- `agents/doc-writer.md` → `.claude/agents/doc-writer.md`
- `agents/security-auditor.md` → `.claude/agents/security-auditor.md`

## MCP
- `mcp/mcp.json` → `./.mcp.json` (project-scoped)
- `mcp/servers-cookbook.md` → `docs/mcp-servers.md` (reference, optional)

## UI / status
- `ui/statusline.sh` → `.claude/hooks/statusline.sh`
- `ui/output-styles/plan.md` → `.claude/output-styles/plan.md`

## How settings merge works

When multiple modules add `hooks`, they must be merged into one `settings.json`. The configurator does this automatically. If you're hand-copying, the pattern is:

```json
{
  "hooks": {
    "PreToolUse": [ ...all matchers from all modules... ],
    "PostToolUse": [ ... ],
    "Stop": [ ... ]
  }
}
```

Within one event name, hooks from different modules concatenate. Claude runs all matching entries.
