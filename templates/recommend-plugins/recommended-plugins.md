# Recommended Claude Code plugins

Generated for `{{project_name}}` on {{generation_date}} from your `.claude-config.json`. Re-run `cc-configure` to refresh this list whenever the form answers change.

These are plugins from the official `claude-plugins-official` marketplace that complement your stack and the configurator's baseline. Install with `claude /plugin install <name>`. See [`10-plugin-ecosystem.md`](10-plugin-ecosystem.md) for how plugins relate to the configurator-shipped surfaces.

## Always recommended (universal)

| Plugin | Why |
|---|---|
| `claude-code-setup` | Codebase-aware automation recommender (`claude-automation-recommender` skill). After scaffold, ask Claude "recommend automations for this project" to discover stack-specific plugins beyond this static list. |
| `claude-md-management` | `claude-md-improver` skill audits and tightens `CLAUDE.md` files against quality criteria. Complementary to the configurator's `/sync-docs` and `/session-retro`. |
| `feature-dev` | Anthropic-maintained `code-architect`, `code-reviewer`, `code-explorer` agents with confidence-based filtering. Richer than the configurator's `code-reviewer` baseline; consider swapping. |
| `commit-commands` | Anthropic-maintained `/commit`, `/commit-push-pr`, `/clean_gone`. Richer than the configurator's `/commit`; consider swapping. |
| `superpowers` | Brainstorming (design-first dev), subagent-driven development with built-in code review, systematic debugging, red/green TDD. **Especially valuable for new projects** — `/brainstorm` enforces a no-implementation-until-design-approved gate. |

## Stack-specific (from your form answers)

{{recommended_plugins}}

## Optional / commonly useful

| Plugin | Why |
|---|---|
| `skill-creator` | Author / improve / evaluate new skills with variance analysis |
| `plugin-dev` | Comprehensive toolkit for authoring Claude Code plugins (7 expert skills) |
| `mcp-server-dev` | Skills for designing and building MCP servers — deployment models, tool design, auth patterns |
| `session-report` | HTML report from `~/.claude/projects/` transcripts: tokens, cache efficiency, subagents, most-expensive prompts |

## Notes

- Plugin versions move; `claude /plugin install <name>` installs the current latest.
- Run `claude /plugin list` to see what's already installed in this project.
- See [`10-plugin-ecosystem.md`](10-plugin-ecosystem.md) §"Swapping configurator skills for plugin equivalents" for the swap path.
- This file regenerates on every `cc-configure` run. Don't hand-edit; tweak your form answers + the `recommend-plugins` module instead.
