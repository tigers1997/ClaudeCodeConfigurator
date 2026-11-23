# AGENTS.md

Instructions for coding agents working in this repository (Codex, Cursor, Copilot's agent, Gemini CLI and others).

## What this is

`cc-configure` (ClaudeCodeConfigurator) is a stdlib-only Python CLI (`configure.py`, `config_schema.py`) that scaffolds a Claude Code configuration, and optionally files for other agent tools, into a project from the templates under `templates/`. Python 3.8 is the floor and there are no third-party Python dependencies. See `CONTRIBUTING.md` for the contributor flow.

## Commands

- `python3 configure.py --check` checks the module registry and the templates. It must pass.
- `bash test/<module>/test-*.sh`, run from the repository root, are the fixture tests. CI runs all of them.
- `python3 configure.py --persona solo-experienced --yes --dir <scratch>` scaffolds into a scratch directory so you can read the output.

## Code Review Rules

These are what pull requests are held to. The Claude gate in `.github/workflows/review.yml` enforces its own blocking list (correctness, licence and MIT integrity, CHANGELOG, schema hygiene, scope). The rules below overlap with it, add secrets, workflow safety and claims, and are what the independent Codex reviewer in `.github/workflows/holdout-review.yml` reads. Report each finding as Critical, Warning or Suggestion by its impact; a violation of rules 1 to 4 is normally Critical.

1. **Correctness and regressions.** Broken validation, a snapshot under `examples/` that no longer matches the generated output, a failing fixture test under `test/`, a construct that Python 3.8 does not support, or a new third-party Python dependency.
2. **Licence integrity.** Third-party code added without a `NOTICE` entry, or under a licence that is incompatible with AGPL-3.0 (proprietary, GPL-2-only, unknown). `templates/discipline-skills/` must stay MIT-clean.
3. **Secrets and identity.** A credential, token, tenant or workspace identifier, personal email address, or a real customer or employer name in code, docs, fixtures, commit messages or PR text.
4. **Workflow safety.** In `.github/workflows/` and in workflow templates: every action pinned to a full commit SHA, least-privilege `permissions`, no `pull_request_target`, no untrusted text (PR title, body, branch name, commit messages) in a shell command or a prompt, and secrets used only as `env` or `with` values.
5. **Scope.** One logical change per PR. Recommend a split when a PR mixes unrelated changes.
6. **CHANGELOG.** A user-visible change (feat, fix, breaking) needs an entry under `## Unreleased`, in the single-bullet style of its neighbours. Docs and chore PRs may skip it. Titles and commits follow Conventional Commits.
7. **Settings schema hygiene.** A key added to a `settings.json` template must exist in the published Claude Code settings schema. Cite the source.
8. **Claims match checks.** A doc or CHANGELOG line that says something was verified must say how, and must say what was not verified.
