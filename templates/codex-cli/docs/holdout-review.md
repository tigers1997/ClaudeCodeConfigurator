# Holdout review (Codex on pull requests)

`.github/workflows/holdout-review.yml` runs OpenAI's Codex, read-only, over each pull request's diff and keeps one comment up to date with its findings. It is advisory: it never fails a PR and is not a merge gate.

## Set it up

Repository **Settings → Secrets and variables → Actions**:

| Kind | Name | Value |
|---|---|---|
| Secret | `CODEX_API_KEY` | Your OpenAI API key, or your Azure OpenAI key |
| Variable | `CODEX_REVIEW_MODEL` | The model to review with. On Azure this is your **deployment name**. Suggested: `{{codex_review_model}}` |
| Secret (a variable in a private repository) | `CODEX_RESPONSES_ENDPOINT` | Azure only: `https://<resource>.openai.azure.com/openai/v1/responses` (the full URL, including `/v1/responses`). Leave it unset for OpenAI. |
| Variable | `CODEX_REVIEW_EFFORT` | Optional: `low`, `medium` or `high` (default `high`) |

**Make the endpoint a secret in a public repository.** The run log prints a step's inputs, a variable's value is not masked, and a public repository's logs are public, so a variable would show your Azure resource name in every run. The workflow reads the secret first and falls back to a variable of the same name.

The workflow fails fast with a clear error when the secret is missing, or when the endpoint is set without a model. Run the smoke test in `docs/codex-setup.md` against the same model first: a deployment that does not answer there will not answer here.

## What it does, and the choices behind it

- **Same-repository pull requests only** (no drafts, no forks). GitHub gives fork PRs no secrets anyway, and a fork is exactly the untrusted code that must never sit next to the key.
- **Dependabot PRs are skipped.** GitHub gives Dependabot-triggered runs no Actions secrets, so a review could only fail its configuration check. To review them, add `CODEX_API_KEY` (and the endpoint) as Dependabot secrets and remove the `github.actor` condition from the `review` job.
- **Read-only.** Codex runs with the `:read-only` permission profile, and the action removes the runner user's `sudo` before Codex starts (`drop-sudo`), which is the action's documented way to keep the API key out of Codex's reach. The job's token is `contents: read`. The job that posts the comment holds the write token and never runs Codex.
- **A PR cannot change the rules it is reviewed against.** The review rules are the `## Code Review Rules` section of `AGENTS.md` **on the base commit**, passed in the prompt, and Codex's own `AGENTS.md` loading is switched off for the run (`project_doc_max_bytes=0`). The PR title, body, branch name and commit messages never enter the prompt. A same-repository PR can still edit the workflow itself: see below.
- **One comment, updated in place**, found by its author and a leading marker. It names the commit it reviewed and is not posted if the PR head has moved on, so a re-run of an old event cannot overwrite a newer review. `@mentions` are neutralised so model output cannot ping people, and `VERDICT:` is neutralised so a workflow that scans PR comments for a verdict cannot mistake this comment for one. Superseded runs are cancelled, but a re-run is a separate attempt: it does not cancel the newest review, and posts nothing if its commit is no longer the PR head.
- **A key never goes to the wrong provider.** Without an endpoint the action sends the key to `api.openai.com`, so the workflow refuses a key that does not start with `sk-` unless `CODEX_RESPONSES_ENDPOINT` is set.
- **Actions are pinned by commit SHA** (the `# v...` comments name the version). Update them on purpose; Dependabot's `github-actions` ecosystem can propose bumps.

## What it does not protect against

- **A branch in this repository can change this workflow.** On `pull_request` events the PR's own copy of the workflow runs, with the secret. Anyone who can push a branch here is therefore trusted with `CODEX_API_KEY`. CODEOWNERS and branch protection decide what merges, not what runs on a pull request, so they do not change that. Give write access only to people you would trust with the key, or keep the key in an Environment with required reviewers (add `environment: <name>` to the `review` job), which makes each run wait for an approval.
- **A retargeted PR keeps its old review.** The workflow runs on pushes, not on edits, so changing a PR's base branch does not trigger a new review: push a commit or re-run the latest run. Running on `edited` would let every title edit cancel a review in flight.
- **Prompt injection is reduced, not removed.** Code comments, file contents and the diff can still try to steer the model. The review is advice: check a finding before acting on it.
- **Cost.** One model run per push to every same-repo PR. Add a `paths:` filter under `pull_request:` if that is too much.

## Limits

- **Runners.** GitHub-hosted Ubuntu. The Codex action has no supported sandbox on Windows runners. On a self-hosted runner, `drop-sudo` changes the runner for the rest of the job, so use ephemeral runners.
- **Azure and Foundry.** The action documents Azure OpenAI (`responses-api-endpoint`); Foundry is not named in its docs, though the endpoint shape is the same. Entra ID sign-in is not available for Codex, so the key is an API key. See the Foundry caveat in `docs/codex-setup.md`.
- **Codex version.** The action installs the latest Codex unless you set its `codex-version` input, and `permission-profile` needs Codex 0.138.0 or later. Pin a version you have tested if you need stable behavior.
- **Not a gate.** Making this a required check would give a model veto power over merges. If you do it anyway, make sure a human can override it.

## Sources (checked 2026-11-23)

- github.com/openai/codex-action: README, docs/security.md, and action.yml at v1.14
- learn.chatgpt.com/docs/github-action
