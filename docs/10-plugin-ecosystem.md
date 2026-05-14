# The plugin ecosystem and the configurator

Claude Code has a plugin system. The official marketplace (`claude-plugins-official`) ships ~170 plugins covering commodity skills, agents, hooks, MCP servers, and vendor integrations. The configurator and the ecosystem are **adjacent, not competing** — and most projects benefit from using both.

This doc explains the relationship and recommends a workflow.

## Two different problems

| | Configurator | Plugins |
|---|---|---|
| **What it generates** | A project-specific deterministic baseline: `CLAUDE.md` from form answers, `.claude/settings.json`, hooks, the modules you opted into | Reusable, installable capabilities (skills, agents, MCPs, hooks) |
| **How it's customized** | Form intake or `--config` JSON; scriptable; reproducible from a saved config | `/plugin install <name>`; per-project enabled/disabled state |
| **Who maintains it** | You (this repo's templates) | Anthropic (or third parties for community plugins) |
| **What changes between versions** | You explicitly via the templates | Upstream — plugin authors ship new versions |

The configurator is good at "set up *this* project deterministically." Plugins are good at "give me *that* capability everywhere I need it." They compose.

## Where official plugins overlap configurator surfaces

Some configurator-shipped surfaces have direct or near-direct plugin equivalents:

| Configurator | Plugin equivalent | Notes |
|---|---|---|
| `commands-core` skills (`/plan`, `/review`, `/commit`, `/ship`) | `feature-dev` plugin (3 agents + `/feature-dev` command) and `commit-commands` plugin (`/commit`, `/commit-push-pr`, `/clean_gone`) | Plugins are Anthropic-maintained and richer; the configurator's are simpler defaults you can edit. Either-or, not both. |
| `code-reviewer` subagent | `feature-dev`'s `code-reviewer` agent (with confidence-based filtering) | Plugin version is more sophisticated; ours is a simpler baseline. |
| `/sync-docs`, `/session-retro` | `claude-md-management` plugin (`claude-md-improver` skill + `/revise-claude-md`) | Different focus: ours captures session learnings; theirs audits any CLAUDE.md against quality criteria. Complementary; both can coexist. |
| `safety` hooks (`block-dangerous-bash.sh`, `scan-secrets.sh`) | `security-guidance` plugin + `hookify` plugin | Ours are static bash scripts; the plugin path lets you author hooks via markdown rules. |
| `/check-context` | `session-report` plugin | Different shape: ours is real-time advice; theirs is post-hoc HTML analytics. |

## Where the configurator stays unique (no plugin equivalent)

These solve problems plugins don't address:

- **Form-driven intake** — interactive picker → `CLAUDE.md` / `.claude/settings.json` / `.mcp.json` written from answers
- **Stack presets** — picking `Python (uv)` prefills test/lint/typecheck/build/install commands and downstream skill content
- **Retrofit safety** — deep-merge for structured assets, skip-and-stage for file collisions, CLAUDE.md merge-append
- **Preflight architecture** — `--check` CI gate, `[ SCHEMA | HOOK | MODULE | VERSION ]` warnings before scaffold
- **Deterministic versioning** — same `.claude-config.json` reproduces the same scaffold across machines and configurator versions

## Where the official ecosystem stays unique

- **Vendor integrations** — Stripe, MongoDB, Neon, Sentry, Linear, Atlassian, Notion, Figma, … (100+). The configurator doesn't try to provide these.
- **Recency** — Anthropic-maintained plugins reflect current best practice; the configurator's templates are point-in-time snapshots.
- **The recommender** — `claude-code-setup`'s `claude-automation-recommender` skill scans a codebase and suggests automations. Useful complement to the configurator's deterministic baseline.

## Recommended workflow

### For a brand-new project

See [`11-getting-started.md`](11-getting-started.md) for the full walkthrough. Headline:

```
claude /plugin install superpowers          # design-first brainstorming
claude                                      # describe what you want — brainstorming skill auto-triggers
# (capture the design to docs/design.md)
cc-configure                                # answers shaped by the design
# (configurator emits docs/recommended-plugins.md if the recommend-plugins module is enabled)
claude /plugin install <stack-specific>     # install what the recommendations doc surfaces
```

### For an existing project

```
cc-configure --dry-run                      # preview
cc-configure                                # non-destructive: deep-merge + skip-stage + append
claude /retrofit                            # walk .claude-retrofit/REPORT.md interactively
# delete .claude-retrofit/ when done
```

### For ongoing maintenance

- `claude-md-management` plugin's `/revise-claude-md` to audit and tighten the project's CLAUDE.md
- `claude-code-setup`'s `/recommend-automations` to discover stack-specific plugins as the project grows
- `cc-configure --check` in CI to ensure shipped templates stay valid (only relevant if you fork or extend the configurator's templates)

## Swapping configurator skills for plugin equivalents

If you want to drop the configurator's `commands-core` skills in favor of `feature-dev` + `commit-commands`:

1. Run `cc-configure` without `commands-core` in the selected modules
2. Install the plugins: `claude /plugin install feature-dev commit-commands`
3. Delete `.claude/skills/{plan,review,ship,commit,sync-docs,session-retro,verify-setup,check-context}/` (your fork is replaced by the plugin's)
4. Keep `agents` — `code-reviewer` is the only specialist that the plugin's `feature-dev` agent overlaps; `test-runner` / `doc-writer` / `security-auditor` (with Sonatype) are configurator-specific

You're trading "deterministic, fork-able templates I control" for "Anthropic-maintained, latest-version plugins." Both are valid; the swap is reversible.

## Future direction

A v2.x of the configurator may re-architect around plugins: instead of copying skill/agent files, the scaffolded output declares which plugins to install (via a `.claude-plugin/plugin.json` or a bootstrap script). The configurator's job becomes "generate the project-specific glue (CLAUDE.md, settings.json, hooks)" while delegating commodity content to upstream. Tracked as a v2 item in the local backlog.

For now (v1.x), the configurator and plugins coexist. Use the `recommend-plugins` module (since v1.3.0) to get a project-specific list of what to install alongside the scaffold.
