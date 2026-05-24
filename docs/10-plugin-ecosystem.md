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

## Discipline skills: bundled vs. upstream plugin

The configurator ships a `discipline-skills` module — a curated 7-skill subset forked from the MIT-licensed `obra/superpowers` v5.1.0 plugin: `brainstorming`, `writing-plans`, `executing-plans`, `verification-before-completion`, `using-git-worktrees`, `subagent-driven-development`, `finishing-a-development-branch`. They land at project-level `.claude/skills/<name>/SKILL.md`. A slim SessionStart hook (`sessionstart-discipline.sh`) primes the model with a terse seven-skill bootstrap.

**Why ship a fork instead of just recommending the upstream plugin:**

- **~930 tokens saved per session.** Full superpowers injects ~1,200 tokens at SessionStart via `using-superpowers` plus ~270 tokens of skill descriptions for 14 skills. The configurator's bootstrap is ~400 tokens and we ship 7 skill descriptions, totaling ~540 — a ~63% reduction in fixed session-overhead for these capabilities.
- **Curation control.** The configurator picks which 7 skills earn the context cost. The other 7 upstream skills (`systematic-debugging`, `test-driven-development`, `dispatching-parallel-agents`, `requesting-code-review`, `receiving-code-review`, `writing-skills`, `using-superpowers`) overlap configurator-shipped equivalents (`/investigate`, `multi-agent-guardrails.md`, `/review`, `code-reviewer` agent) or are too meta for the default kit.
- **Rugpull immunity.** Upstream v5.1.0 (2026-04-30) removed three slash commands (`/brainstorm`, `/write-plan`, `/execute-plan`) — that broke configurator references and required a cleanup PR. A forked-snapshot module stays stable until we choose to sync.
- **Plugin-skill namespacing means no conflict.** Per `code.claude.com/docs/en/skills`: *"Plugin skills use a `plugin-name:skill-name` namespace, so they cannot conflict with other levels."* If a user installs both this module and the upstream plugin, the configurator's bootstrap auto-suppresses (detects `~/.claude/plugins/cache/claude-plugins-official/superpowers/`) and the two coexist. `/verify-setup` Check #12 flags the duplication so the user can pick one.

**When to use which:**

| Situation | Recommendation |
|---|---|
| `solo-newer`, `solo-experienced`, `small-team` personas | `discipline-skills` module (default — already in the persona's module set) |
| You want the *full* upstream methodology including TDD, systematic-debugging, parallel-agents, code-review patterns | `claude /plugin install superpowers` (skip or uninstall `discipline-skills`) |
| You want both | Allowed — namespacing prevents conflicts. The configurator's bootstrap will auto-suppress; check `/verify-setup` Check #12. |
| You want neither (lean baseline) | `cc-configure` without `discipline-skills` in selected modules |

**Upstream-sync workflow:** see `templates/discipline-skills/SYNC.md` (maintainer-internal, not shipped). Every cc-configure release that includes a discipline-skills bump cites the upstream version in the CHANGELOG.

## Future direction

A v2.x of the configurator may re-architect around plugins: instead of copying skill/agent files, the scaffolded output declares which plugins to install (via a `.claude-plugin/plugin.json` or a bootstrap script). The configurator's job becomes "generate the project-specific glue (CLAUDE.md, settings.json, hooks)" while delegating commodity content to upstream. Tracked as a v2 item in the local backlog.

For now (v1.x), the configurator and plugins coexist. Use the `recommend-plugins` module (since v1.3.0) to get a project-specific list of what to install alongside the scaffold.
