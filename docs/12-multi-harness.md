# Multi-harness projects

One repository, more than one agent tool: Claude Code plus Codex CLI, Gemini CLI, Cursor, Copilot's agent, and so on. This doc covers what each tool reads, how the `agents-md` module shares one set of project facts between them, and what a repository can and cannot control about which model does what.

Everything below was checked against each tool's official documentation in November 2026 (sources at the end). These tools change monthly; re-check before relying on a detail.

## Who reads what

| Tool | Instruction file it reads | Notes |
|---|---|---|
| **Claude Code** | `CLAUDE.md` (and files it `@`-imports) | Reads `AGENTS.md` **only when no `CLAUDE.md` exists** in the working directory or any parent (2.1.277+). With both, it reads `CLAUDE.md` alone. |
| **Codex CLI** | `AGENTS.md` | Walks from the repo root to the working directory; per directory it takes `AGENTS.override.md`, else `AGENTS.md`, else `project_doc_fallback_filenames`. Concatenated root-first, capped at 32 KiB (see [Budget](#the-32-kib-budget)). |
| **Gemini CLI** | `GEMINI.md` | Reads `AGENTS.md` only if `context.fileName` lists it. A `GEMINI.md` containing `@./AGENTS.md` needs no setting. |
| **Cursor** | `AGENTS.md` at the root and in subdirectories | `.cursor/rules/*.mdc` is optional extra. |
| **GitHub Copilot** | `.github/copilot-instructions.md` everywhere | `AGENTS.md` is read by the cloud agent, GitHub.com code review, VS Code chat and Copilot CLI, but not by Copilot Chat on GitHub.com, Visual Studio, JetBrains or Xcode chat. If you rely on those surfaces, add a short `copilot-instructions.md`; this module does not write one. |
| **Zed, Windsurf, Amp, Aider, Warp, ...** | `AGENTS.md` | See the list at agents.md. It is self-reported; Claude Code is not on it. |

## What the `agents-md` module writes

`cc-configure --harness agents-md` (or the quick-mode harness question) turns on three behaviors:

- **`AGENTS.md`** holds the harness-neutral half of your project memory: goals, stack, commands, code style, testing, git workflow, design notes, gotchas, CLIs, plus an **Agent roles** section and a **Code Review Rules** section. Codex's GitHub-hosted review reads a `## Code Review Rules` section from the nearest `AGENTS.md`, so it doubles as a reviewer checklist for any harness.
- **`CLAUDE.md`** becomes a bridge: its first line is `@AGENTS.md`, followed by only what is specific to Claude Code (repo bootstrap, collaboration patterns, behavior rules, token-efficiency rules, MCP servers).
- **`GEMINI.md`** (with `--harness gemini`) imports `AGENTS.md`.

Edit project facts in `AGENTS.md`. Keep `CLAUDE.md` for Claude Code specifics. Commit both.

Why an import rather than a symlink (`ln -s AGENTS.md CLAUDE.md`): a symlink cannot hold Claude-only content, Claude Code's Edit and Write tools refuse to write through it, and on Windows Git checks it out as a plain file unless `core.symlinks` is enabled.

A Claude-only scaffold (no `--harness`) is unchanged: one `CLAUDE.md`, no `AGENTS.md`.

### Choosing harnesses

| Where | How |
|---|---|
| Quick mode | Question 4 of 6. `Enter` keeps what a saved config already selects, `0` clears, `1,2,3` picks several. Picking Codex adds one follow-up: whether to add the PR review workflow. |
| Flag | `--harness agents-md,gemini,codex`. It **replaces** the saved harness set; `claude-code` or `none` means Claude Code only. Other modules are untouched. `--codex-ci` (needs `--harness codex`) also writes the PR review workflow. |
| Detailed mode | The module checklist lists `agents-md`, `gemini-cli` and `codex-cli`; the Codex form fields are prompted too. |

### Retrofitting an existing repo

The configurator never edits your `CLAUDE.md` beyond the usual value-add sections, and it does not insert `@AGENTS.md` for you: your `CLAUDE.md` almost certainly states the same project facts already, and importing `AGENTS.md` on top would load them twice. Instead it warns (`[ MODULE WARNINGS ]`, `[ NEXT STEPS ]`, and `.claude-retrofit/REPORT.md`). To finish by hand:

1. Move the harness-neutral facts from `CLAUDE.md` into `AGENTS.md` (an existing `AGENTS.md` of yours is kept and ours is staged under `.claude-retrofit/incoming/`).
2. Add `@AGENTS.md` as the first line of `CLAUDE.md`.
3. Run `/verify-setup`: check 18 confirms the import and the size budget.

If a `CLAUDE.md` exists in a *parent* directory, or a gitignored `CLAUDE.local.md` exists, Claude Code ignores `AGENTS.md` entirely. That is another reason to keep the bridge in the repo root.

## Codex CLI (`--harness codex`)

The `codex-cli` module pairs Claude Code with OpenAI's Codex CLI as an **independent reviewer**: a model from another family reads your diff cold, so it does not share the author's blind spots. It depends on `agents-md` because Codex reads `AGENTS.md` natively, including the **Code Review Rules** section.

| Writes | When | What it is |
|---|---|---|
| `docs/codex-setup.md` | always | The user-level `~/.codex` config for OpenAI or Azure/Microsoft Foundry, `review` and `bulk` profile files, a smoke test, version pinning and the known caveats. |
| `.claude/skills/cross-review/` | `cross_review` (default on) | `/cross-review`: a script runs `codex exec --sandbox read-only --ephemeral` over the branch diff, then Claude re-checks every finding against the code before showing it. Codex invocations are `ask` permission rules, because repository content goes to another vendor. |
| `.github/workflows/holdout-review.yml`, `docs/holdout-review.md` | `holdout_ci` (`--codex-ci`, default off) | An advisory PR review on `openai/codex-action`: SHA-pinned, read-only, same-repository PRs only, review rules read from the base commit. Needs a `CODEX_API_KEY` secret. |

**Why there is no `.codex/config.toml`.** Codex ignores `model_provider`, `model_providers`, `profile`, `profiles` and base-URL keys in a project's `.codex/config.toml`, and loads project config only for trusted projects, so a cloned repository cannot redirect where your credentials go. The provider, its `env_key` and your profiles live in `~/.codex`; `docs/codex-setup.md` gives you templates instead.

**Profiles are overlay files.** `~/.codex/<name>.config.toml` holds top-level keys and is selected with `--profile <name>`. The `[profiles.<name>]` tables in older guides were removed in Codex 0.134.0, and `--profile` now errors while they remain. `/verify-setup` check 19 looks for them.

**Model names are form fields**, not constants (`codex_provider`, `codex_review_model`, `codex_bulk_model`, `codex_review_effort`), because on Azure `model` is the name of *your deployment*. The defaults, `gpt-6.2-astra` for review and `gpt-6.2-sol` for bulk edits, were current in November 2026. One open report says `gpt-6.2-sol` fails through Foundry on Codex 0.169 to 0.171 (openai/codex#62753): pin a Codex version and run the smoke test in `docs/codex-setup.md`.

**The PR workflow is advisory on purpose.** A model veto over merges is the wrong default, and a PR that can edit its own reviewer should not get to approve itself. `docs/holdout-review.md` lists what the workflow does and, just as important, what it does not protect against (for example, anyone who can push a branch can change the workflow that runs with the key).

## The 32 KiB budget

Codex stops adding instruction files once the combined text reaches `project_doc_max_bytes` (default 32768 bytes) and truncates without a warning. The Codex docs and source disagree on whether the budget is per file or shared across the chain; plan for shared. The scaffolded `AGENTS.md` is about 4 KiB, `--check` fails the build if it renders over 20 KiB, and `/verify-setup` warns above 24 KiB. Put directory-specific rules in a nested `AGENTS.md` rather than growing the root file: Codex loads the ones between the repo root and its working directory, and Claude Code loads one when it reads a file in that directory (only where that directory has no `CLAUDE.md` of its own).

## Models and roles: what a repository can control

- **Claude Code.** A committed `.claude/settings.json` can set a default `model` and `effortLevel`, but it is an initial selection, not enforcement: a developer can `/model` away, override with `ANTHROPIC_MODEL`, or use `settings.local.json`. Only managed settings enforce. The one routing lever a repo does enforce is the `model:` and `effort:` frontmatter of its subagents (see `.claude/agents/`).
- **Other vendors' models.** Claude Code cannot route to non-Claude models through any gateway, and a subagent cannot run another vendor's model. A second harness is a separate process: a person running `codex`, a CI job, or a script that shells out. That is how the `codex-cli` module's cross-vendor reviewer works.
- **Do not put model-routing instructions in `CLAUDE.md` or `AGENTS.md`.** They load every turn, and the model cannot switch its own model. Write the role-to-model table where humans read it (`docs/`).

## Trust

- An `AGENTS.md` that arrives in a pull request is untrusted input to any agent that reads it. A CI job that runs an agent over a PR must not give it secrets the PR can reach.
- Repo-supplied hooks and `.mcp.json` servers can run under `claude -p` or the Agent SDK in a checkout you have not reviewed. Review `.claude/settings.json` and `.mcp.json` in third-party repos before running Claude Code non-interactively in them.

## Sources (accessed 2026-11-22/23)

- Claude Code: code.claude.com/docs/en/memory, model-config, settings, llm-gateway
- Codex: learn.chatgpt.com/docs/agent-configuration/agents-md, config-file/config-advanced, non-interactive-mode, github-action (the former developers.openai.com/codex paths redirect there); github.com/openai/codex-action (README, docs/security.md, action.yml at v1.14); github.com/openai/codex/issues/62753
- Azure OpenAI with Codex: learn.microsoft.com/en-us/azure/foundry/openai/how-to/codex
- Gemini CLI: github.com/google-gemini/gemini-cli, docs/cli/gemini-md.md and docs/reference/configuration.md
- Cursor: cursor.com/docs/rules
- GitHub Copilot: docs.github.com/en/copilot/reference/custom-instructions-support
- agents.md (the format and the compatible-tool list)
