# Codex CLI setup

This repo pairs Claude Code with OpenAI's Codex CLI as an independent reviewer: a model from another family reads your diff cold. Configured provider: **Azure OpenAI / Microsoft Foundry**.

Everything on this page happens on your machine (and in CI), not in the repository. A repository cannot choose a Codex provider: Codex ignores `model_provider`, `model_providers`, `profile`, `profiles` and base-URL keys in a project's `.codex/config.toml`, so a cloned repo cannot redirect where your credentials are sent. That is why this scaffold ships no `.codex/config.toml`.

## 1. Install and pin Codex

```bash
npm install -g @openai/codex@<version>     # or: brew install --cask codex
codex --version
```

Pin a version you have tested. Provider support moves with releases, and Microsoft's Azure guide describes the versions it validated as "validated versions, not minimum supported versions". Codex 0.134.0 also removed `[profiles.*]` tables from `config.toml` (step 3).

## 2. Provider config: `~/.codex/config.toml`

```toml
# ~/.codex/config.toml
model = "gpt-6.2-sol"   # your Azure DEPLOYMENT name, not the model family
model_provider = "azure"
model_reasoning_effort = "medium"

[model_providers.azure]
name = "Azure OpenAI"
base_url = "https://YOUR_RESOURCE_NAME.openai.azure.com/openai/v1"
env_key = "AZURE_OPENAI_API_KEY"
wire_api = "responses"
```

- **OpenAI:** sign in as described in the Codex docs (learn.chatgpt.com/docs). For `codex exec` in automation, Codex reads `CODEX_API_KEY`; set it only on the one command that needs it, never for a whole job.
- **Azure OpenAI / Microsoft Foundry:** `model` is the name of **your deployment**, not the model's own name. Use the v1 `base_url` (`.../openai/v1`, no `api-version`). `wire_api = "responses"` is the only value Codex accepts. `env_key` names an environment variable (`export AZURE_OPENAI_API_KEY=...`); never put the key in the file. Microsoft states that Entra ID sign-in is not available for Codex, so this is API-key only.
- **Known issue (not reproduced):** openai/codex#62753 reports `gpt-6.2-sol` failing through Foundry on Codex 0.169 to 0.171 with an invalid tool-schema error, while `gpt-6.1-sol` works. On 2026-11-23 a smoke test with `gpt-6.2-sol`, one with `gpt-6.2-astra` and a `/cross-review` run all passed through a Foundry resource on Codex 0.171.0, so the report may be specific to a deployment or already fixed. Smoke-test your own deployment (step 4) and keep the Codex version pinned.

## 3. Profiles: `~/.codex/<name>.config.toml`

A profile is an overlay file with top-level keys only, selected with `--profile <name>`.

```toml
# ~/.codex/review.config.toml: used by `codex --profile review` and by /cross-review
model = "gpt-6.2-astra"
model_reasoning_effort = "high"
```

```toml
# ~/.codex/bulk.config.toml: bulk, deterministic edits: `codex --profile bulk`
model = "gpt-6.2-sol"
model_reasoning_effort = "medium"
```

- Do not copy `[profiles.review]` tables from older guides. Since Codex 0.134.0, `--profile` errors if `config.toml` still contains them.
- A profile name with no file is reported to be treated as an empty layer, not an error. If `--profile review` seems to change nothing, check the file name.
- The model names above were current when this was scaffolded (`gpt-6.2-astra` and `gpt-6.2-sol`, released 2026-11-17). To change them, edit `model` in `~/.codex/config.toml`, `~/.codex/review.config.toml` and `~/.codex/bulk.config.toml`; the PR review in CI takes its model from the `CODEX_REVIEW_MODEL` repository variable. `cc-configure` does not write to `~/.codex`, and re-running it on a project that already has this guide keeps your copy by default (`--on-collision=skip`) and stages the new one in `.claude-retrofit/incoming/docs/`, so `codex_review_model` and `codex_bulk_model` in `.claude-config.json` only change what a newly scaffolded guide shows.

## 4. Smoke test

```bash
codex exec --sandbox read-only --ephemeral "Reply with the single word OK."
codex exec --profile review --sandbox read-only --ephemeral "Reply with the single word OK."
```

Both should print `OK`. Do this before trusting a review, and again after upgrading Codex.

Run these in a terminal. In a script, a CI step or Claude Code's Bash tool, add `< /dev/null`: with a prompt argument `codex exec` still reads piped input, appends it to the prompt and waits for it to end, so a command whose input is an open pipe never starts (`/cross-review` already does this).

## 5. Use it

- **In Claude Code:** `/cross-review` (if the `cross_review` option is on). It asks permission, runs `codex exec` read-only over this branch's diff, then Claude re-checks each finding against the code before showing it.
- **By hand:** `codex exec --profile review --sandbox read-only --ephemeral "Review git diff main...HEAD against AGENTS.md"`. `codex exec` is read-only by default; never pass `--yolo` or `--dangerously-bypass-approvals-and-sandbox` for a review.
- **What leaves your machine:** the diff and whatever Codex reads while reviewing go to the provider configured above. Do not run this on repositories you are not allowed to share with that provider.
- **In CI:** see `docs/holdout-review.md` if the `holdout_ci` option is on.

## Sources (checked 2026-11-23)

- Codex configuration: learn.chatgpt.com/docs/config-file/config-advanced
- Codex non-interactive mode: learn.chatgpt.com/docs/non-interactive-mode
- Azure OpenAI with Codex: learn.microsoft.com/en-us/azure/foundry/openai/how-to/codex
