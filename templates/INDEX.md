# Template library index

**Generated — do not edit by hand.** Produced from `MODULES` in
`config_schema.py` by `python3 configure.py --write-index`, and verified
by `python3 configure.py --check`.

Every module contributes drop-in files for a target project. `cc-configure`
composes the selected modules; you can also copy any file directly.

## `core`  *(required)*

CLAUDE.md template (populated from the intake form), .claude/settings.json with balanced permissions, .gitignore additions.

| Template | Installs to |
|---|---|
| `core/CLAUDE.md` | `CLAUDE.md` |
| `core/dot-claude/settings.json` | `.claude/settings.json` |
| `core/dot-claude/settings.local.json.example` | `.claude/settings.local.json.example` |

- `core/.gitignore.append` appends to `.gitignore`
- `core/.gitattributes.append` appends to `.gitattributes`

## `safety`

PreToolUse hooks (block dangerous bash: rm -rf, sudo, curl | sh, force push, hard reset; gate apt/brew/dnf/yum/pacman/apk install for packages not in any configured repo) + scan Write/Edit for secrets.

| Template | Installs to |
|---|---|
| `safety/hooks/block-dangerous-bash.sh` | `.claude/hooks/block-dangerous-bash.sh` |
| `safety/hooks/scan-secrets.sh` | `.claude/hooks/scan-secrets.sh` |
| `safety/hooks/check-package-availability.sh` | `.claude/hooks/check-package-availability.sh` |
| `safety/hooks/_lib/availability_check.sh` | `.claude/hooks/_lib/availability_check.sh` |
| `safety/hooks/_lib/detect_tool_versions.sh` | `.claude/hooks/_lib/detect_tool_versions.sh` |

- `safety/settings-patch.json` merges into `.claude/settings.json`
- flag `lockdown`
- flag `slop_scan`
- flag `slop_scan_action` (warn | block, default `warn`)
- flag `slop_scan_density`
- flag `slop_scan_imports`

## `git-workflow`

PostToolUse formats files after Claude writes (prettier/ruff/gofmt/rustfmt).

| Template | Installs to |
|---|---|
| `git-workflow/hooks/format-on-write.sh` | `.claude/hooks/format-on-write.sh` |
| `git-workflow/hooks/stop-run-checks.sh` | `.claude/hooks/stop-run-checks.sh` |

- `git-workflow/settings-patch.json` merges into `.claude/settings.json`

## `token-efficiency`

Path-scoped .claude/rules/ starters + PreCompact snapshot.

| Template | Installs to |
|---|---|
| `token-efficiency/dot-claude/rules/_scoping-guide.md` | `.claude/rules/_scoping-guide.md` |
| `token-efficiency/dot-claude/rules/frontend.md` | `.claude/rules/frontend.md` |
| `token-efficiency/dot-claude/rules/backend.md` | `.claude/rules/backend.md` |
| `token-efficiency/dot-claude/rules/tests.md` | `.claude/rules/tests.md` |
| `token-efficiency/hooks/pre-compact-snapshot.sh` | `.claude/hooks/pre-compact-snapshot.sh` |

- registers hook entries in `.claude/settings.json`
- flag `tier` (basic | pro, default `basic`)

## `commands`

Bundled commands (plan/review-branch/commit/ship/sync-docs/check-context/session-retro/verify-setup/retrofit) + 4 subagents (code-reviewer/test-runner/doc-writer/security-auditor).

| Template | Installs to |
|---|---|
| `commands/plan/SKILL.md` | `.claude/skills/plan/SKILL.md` |
| `commands/review-branch/SKILL.md` | `.claude/skills/review-branch/SKILL.md` |
| `commands/commit/SKILL.md` | `.claude/skills/commit/SKILL.md` |
| `commands/ship/SKILL.md` | `.claude/skills/ship/SKILL.md` |
| `commands/sync-docs/SKILL.md` | `.claude/skills/sync-docs/SKILL.md` |
| `commands/check-context/SKILL.md` | `.claude/skills/check-context/SKILL.md` |
| `commands/session-retro/SKILL.md` | `.claude/skills/session-retro/SKILL.md` |
| `commands/verify-setup/SKILL.md` | `.claude/skills/verify-setup/SKILL.md` |
| `commands/retrofit/SKILL.md` | `.claude/skills/retrofit/SKILL.md` |
| `commands/agents/code-reviewer.md` | `.claude/agents/code-reviewer.md` |
| `commands/agents/test-runner.md` | `.claude/agents/test-runner.md` |
| `commands/agents/doc-writer.md` | `.claude/agents/doc-writer.md` |
| `commands/agents/security-auditor.md` | `.claude/agents/security-auditor.md` |
| `commands/freeze/SKILL.md` | `.claude/skills/freeze/SKILL.md` |
| `commands/unfreeze/SKILL.md` | `.claude/skills/unfreeze/SKILL.md` |
| `commands/guard/SKILL.md` | `.claude/skills/guard/SKILL.md` |
| `commands/careful/SKILL.md` | `.claude/skills/careful/SKILL.md` |
| `commands/microbit-enforcer/microbit-enforcer.sh` | `.claude/hooks/microbit-enforcer.sh` |

- flag `subset` (curated | full | rigorous, default `full`)

## `recommend-plugins`

Generates docs/recommended-plugins.md listing official Claude Code plugins recommended for your stack: always-recommended set (claude-code-setup, claude-md-management, feature-dev, commit-commands, superpowers, etc.) + stack-specific picks computed from your form answers (language → LSP plugin, database → DB plugin, framework → framework-specific plugin, MCP toggles → official replacements).

| Template | Installs to |
|---|---|
| `recommend-plugins/recommended-plugins.md` | `docs/recommended-plugins.md` |

## `experiments-memory`

Scaffolds memory/experiments/CLAUDE.md — a nested memory file that injects ONLY when Claude reads files under memory/experiments/.

| Template | Installs to |
|---|---|
| `experiments-memory/memory/experiments/CLAUDE.md` | `memory/experiments/CLAUDE.md` |
| `experiments-memory/memory/experiments/2026-04-24-example-profile-budget.md` | `memory/experiments/2026-04-24-example-profile-budget.md` |

## `multi-agent`

Path-scoped guardrails rule (loads when touching .claude/agents/**), /merge-worktrees for safe integration of parallel branches, and /infinite + parallel-generator subagent for fanout-style spec expansion (generate N variants in parallel).

| Template | Installs to |
|---|---|
| `multi-agent/dot-claude/rules/multi-agent-guardrails.md` | `.claude/rules/multi-agent-guardrails.md` |
| `multi-agent/dot-claude/agents/parallel-generator.md` | `.claude/agents/parallel-generator.md` |
| `multi-agent/dot-claude/workflows/spec-fanout.js` | `.claude/workflows/spec-fanout.js` |
| `commands/merge-worktrees/SKILL.md` | `.claude/skills/merge-worktrees/SKILL.md` |
| `commands/infinite/SKILL.md` | `.claude/skills/infinite/SKILL.md` |

- `multi-agent/settings-patch.json` merges into `.claude/settings.json`

## `github-actions`

.github/workflows/claude.yml — triggers anthropics/claude-code-action@v1 on @claude mentions in issues, PR comments, and PR reviews.

| Template | Installs to |
|---|---|
| `github-actions/dot-github/workflows/claude.yml` | `.github/workflows/claude.yml` |

## `mcp`

Writes .mcp.json with only the MCP servers you enabled.

| Template | Installs to |
|---|---|
| `mcp/mcp.json` | `.mcp.json` |
| `mcp/servers-cookbook.md` | `docs/mcp-servers.md` |
| `mcp/claude-ctx.sh` | `claude-ctx` |
| `mcp/profiles/mcp.research.json` | `.mcp.research.json` |
| `mcp/profiles/mcp.frontend.json` | `.mcp.frontend.json` |
| `mcp/profiles/mcp.minimal.json` | `.mcp.minimal.json` |
| `mcp/hooks/sessionstart-drift-check.sh` | `.claude/hooks/sessionstart-drift-check.sh` |

- registers hook entries in `.claude/settings.json`

## `discipline-skills`

Seven discipline skills forked from the MIT-licensed obra/superpowers v6.3.0 plugin: brainstorming, writing-plans, executing-plans, verification-before-completion, using-git-worktrees, subagent-driven-development, finishing-a-development-branch.

| Template | Installs to |
|---|---|
| `discipline-skills/LICENSE` | `.claude/skills/_LICENSE-discipline-skills.md` |
| `discipline-skills/brainstorming/SKILL.md` | `.claude/skills/brainstorming/SKILL.md` |
| `discipline-skills/brainstorming/spec-document-reviewer-prompt.md` | `.claude/skills/brainstorming/spec-document-reviewer-prompt.md` |
| `discipline-skills/writing-plans/SKILL.md` | `.claude/skills/writing-plans/SKILL.md` |
| `discipline-skills/writing-plans/plan-document-reviewer-prompt.md` | `.claude/skills/writing-plans/plan-document-reviewer-prompt.md` |
| `discipline-skills/executing-plans/SKILL.md` | `.claude/skills/executing-plans/SKILL.md` |
| `discipline-skills/verification-before-completion/SKILL.md` | `.claude/skills/verification-before-completion/SKILL.md` |
| `discipline-skills/using-git-worktrees/SKILL.md` | `.claude/skills/using-git-worktrees/SKILL.md` |
| `discipline-skills/subagent-driven-development/SKILL.md` | `.claude/skills/subagent-driven-development/SKILL.md` |
| `discipline-skills/subagent-driven-development/implementer-prompt.md` | `.claude/skills/subagent-driven-development/implementer-prompt.md` |
| `discipline-skills/subagent-driven-development/task-reviewer-prompt.md` | `.claude/skills/subagent-driven-development/task-reviewer-prompt.md` |
| `discipline-skills/subagent-driven-development/re-review-prompt.md` | `.claude/skills/subagent-driven-development/re-review-prompt.md` |
| `discipline-skills/subagent-driven-development/scripts/review-package` | `.claude/skills/subagent-driven-development/scripts/review-package` |
| `discipline-skills/subagent-driven-development/scripts/task-brief` | `.claude/skills/subagent-driven-development/scripts/task-brief` |
| `discipline-skills/subagent-driven-development/scripts/sdd-workspace` | `.claude/skills/subagent-driven-development/scripts/sdd-workspace` |
| `discipline-skills/finishing-a-development-branch/SKILL.md` | `.claude/skills/finishing-a-development-branch/SKILL.md` |
| `discipline-skills/hooks/sessionstart-discipline.sh` | `.claude/hooks/sessionstart-discipline.sh` |

- registers hook entries in `.claude/settings.json`

## `ui`

Status line script (project dir | branch | model | context % | OS+tool-version chip), an alternative 'last-prompt' status line, and a 'plan' output style.

| Template | Installs to |
|---|---|
| `ui/statusline.sh` | `.claude/hooks/statusline.sh` |
| `ui/statusline-last-prompt.sh` | `.claude/hooks/statusline-last-prompt.sh` |
| `ui/output-styles/plan.md` | `.claude/output-styles/plan.md` |

- flag `no_version_chip`

## How settings merge works

Several modules contribute `hooks` entries, and they all land in one
`.claude/settings.json`. The CLI merges them (see `deep_merge_settings` and
`_merge_hook_groups` in `configure.py`): groups are keyed by `matcher`, inner
hooks are unioned by `command`, and a user's own entries are never rewritten.
If you're hand-copying instead, the shape is:

```json
{
  "hooks": {
    "PreToolUse":  [ ...all matchers from all modules... ],
    "PostToolUse": [ ... ],
    "Stop":        [ ... ]
  }
}
```

Within one event, hooks from different modules concatenate; Claude Code runs
every matching entry.

## Path rewrites

- `*/dot-claude/*` -> `.claude/*` and `*/dot-github/*` -> `.github/*`. The
  template tree avoids real dotfolders so it browses and syncs cleanly on
  tools that special-case them.
- `mcp/mcp.json` -> `.mcp.json`; `mcp/profiles/mcp.<name>.json` ->
  `.mcp.<name>.json` at the repo root; `mcp/servers-cookbook.md` ->
  `docs/mcp-servers.md`; `mcp/claude-ctx.sh` -> `claude-ctx` (executable).
- Hook scripts are written executable, and with LF endings on every platform.

## PowerShell hook variants

Six hooks ship a `.ps1` sibling next to the `.sh`:
`block-dangerous-bash`, `scan-secrets`, `format-on-write`, `stop-run-checks`,
`pre-compact-snapshot` and `microbit-enforcer`. They are not listed above
because they are not separate module paths: `--hook-shell powershell` swaps a
`.sh` for its `.ps1` sibling by name at scaffold time and sets
`"shell": "powershell"` on those hook entries only. Hooks with no sibling stay
bash. Shipped `.ps1` files must be ASCII and BOM-free -- PowerShell 5.1 reads
them as ANSI, so a stray em-dash can terminate a string and break parsing.
`--check` enforces both that and the `.sh` pairing.
