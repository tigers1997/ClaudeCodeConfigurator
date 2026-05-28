# Contributing to ClaudeCodeConfigurator

ClaudeCodeConfigurator is a Python tool that scaffolds Claude Code configurations into target projects. This document describes how to contribute. By submitting a pull request, you agree to the terms below.

See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for community expectations.
See [`SECURITY.md`](SECURITY.md) for vulnerability reporting — **do not** file public issues for security problems.

## Your rights as a contributor

- You keep copyright on your code. You can use your own contribution elsewhere.
- You grant the project the right to use, modify, sublicense, and **sell** your contribution under any license, by signing the **SAP Individual Contributor License Agreement** on your first pull request (presented automatically by the cla-assistant.io bot; one-time per contributor).
- You will not be paid for contributions unless a separate written agreement says so.
- The AGPL-3.0 version of the project will remain available under AGPL-3.0. Your contributions don't get retroactively closed-sourced from the community.
- Contributions to `templates/discipline-skills/` are governed by **MIT** (the subtree's own LICENSE file), not AGPL. The subtree's LICENSE file is the authoritative governance for those files; the SAP ICLA's broad sublicensing grant applies to the surrounding AGPL-3.0 code.
- The CLA only covers what you submit after signing; it doesn't retroactively cover prior contributions.

## License compatibility checklist

Before you add third-party code anywhere:

- **Allowed inbound licenses:** AGPL-3.0-compatible — GPL-3.0+, LGPL-3.0+, MIT, BSD-2/3-Clause, Apache-2.0, ISC, Unlicense.
- **`templates/discipline-skills/` accepts only MIT-or-compatible code.** Do not paste AGPL-only code into that subtree.
- Any third-party code added → corresponding entry in [`NOTICE`](NOTICE). One block per source, with copyright + license.
- No proprietary, GPL-2-only, or unknown-license code. Ever.

## Development setup

Requires Python 3.8+ (same floor as the runtime; CI runs 3.11).

```bash
git clone https://github.com/tigers1997/ClaudeCodeConfigurator.git
cd ClaudeCodeConfigurator
python3 configure.py --check
```

`configure.py --check` is the same static validation that CI runs as the `check` status job — clean locally means clean in CI for that gate. Persona snapshots live under `examples/persona-*/expected-tree.txt`; fixture tests under `test/`. Run shell fixtures with `bash test/<dir>/test-*.sh`.

## Branches, commits, signing

- **Branch from `main`** with a descriptive name: `feat/<thing>`, `fix/<thing>`, `docs/<thing>`, `chore/<thing>`, `refactor/<thing>`.
- **Conventional Commits** required in commit messages and PR titles: `feat(scope): summary`, `fix(scope): summary`, etc.
- **Signed commits required.** Use GPG or SSH commit signing. See [GitHub's docs on commit signing](https://docs.github.com/en/authentication/managing-commit-signature-verification). Unsigned commits will be rejected by branch protection on `main`.
- **One logical change per PR.** Reviewers (human and AI) struggle with mixed-purpose PRs; merge friction goes up; rollback gets messy.

## Opening a PR

```bash
gh pr create --fill
```

The PR body is auto-populated from `.github/pull_request_template.md`. Fill checkboxes honestly — they map to the CI checks that have to pass before merge.

**On your first PR:** cla-assistant will comment with a one-click sign link. The `license/cla` status check stays red until you sign. Sign once; future PRs are auto-recognized.

**Required status checks (all must be green to merge):**

1. `check` — static validation + smoke tests + fixture tests + persona snapshots.
2. `ai-review` — the `anthropics/claude-code-action@v1` run itself. Succeeds when the action completes (including the GitHub workflow-modification skip).
3. `verdict-gate` — parses the latest review comment for `VERDICT: PASS|BLOCK|COMMENT-ONLY` and fails on `BLOCK` or missing-VERDICT. This is the load-bearing review gate.
4. `license/cla` — CLA signature confirmation from cla-assistant.io (added to the ruleset after the first PR establishes the exact check name).

## The review gate

Every PR is reviewed by [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) running an AGPL-aware, repo-specific prompt. The review looks for:

- Correctness and regression risk (broken validation; broken persona snapshots; broken fixture tests).
- AGPL contamination (third-party code without a `NOTICE` entry; incompatible-license code).
- `templates/discipline-skills/` MIT integrity (no AGPL-only code in that subtree).
- Missing `CHANGELOG.md` `## Unreleased` entry for user-visible changes.
- Schema-claim hygiene (settings.json keys cross-checked against [SchemaStore](https://github.com/SchemaStore/schemastore)).
- Scope creep (multiple unrelated changes in one PR).

Findings post as a single PR conversation comment beginning with `VERDICT: PASS|BLOCK|COMMENT-ONLY`. A follow-up `verdict-gate` job parses that line; `VERDICT: BLOCK` or missing-VERDICT fails the gate. **No merge is possible while `verdict-gate` is failing — including for the maintainer.**

To re-trigger after addressing findings: push a new commit, or comment `@claude review` on the PR.

To dispute a finding: reply in the PR thread. The maintainer can re-prompt the action with overriding context. Hard override of the gate itself is rare, requires written justification in the PR body, and is recorded in `CHANGELOG.md` under `### Notes`.

**Self-bootstrap escape hatch.** When a PR modifies `.github/workflows/review.yml` itself, GitHub silently skips the modified workflow (a security measure). `verdict-gate` detects this case via the PR's file list and soft-passes — otherwise every workflow-edit PR would have a permanently-red gate.

## CHANGELOG, squash-merge, versioning

- Add a `CHANGELOG.md` entry under `## Unreleased` using Keep-a-Changelog sections: `### Added`, `### Changed`, `### Fixed`, `### Removed`, `### Security`. Format: `- short description (#<PR>, <commit-sha>)`. SHA-anchor after merge.
- Squash-merge by default; one commit on `main` per PR. `gh pr merge --squash --delete-branch` does it.
- Semver from v1.0.0 onward: **patch** = bug fixes; **minor** = new modules / skills / templates, backward-compatible; **major** = invalidates a saved `.claude-config.json` or rewrites template paths.

## Branch protection contract

The settings below are enforced on `main` via `MainBrnchRuleset` (canonical export in [`docs/governance/branch-protection.json`](docs/governance/branch-protection.json)):

- PR required (no direct push).
- Required status checks: `check`, `ai-review`, `verdict-gate`, and `license/cla` (added after the first PR establishes the exact check name).
- Required signed commits (GPG or SSH).
- Required linear history.
- Required conversation resolution before merge (nested under "Require a pull request before merging" in the GitHub ruleset UI).
- Force-push blocked.
- Branch-deletion blocked.
- Bypass actors: none — the maintainer is bound by the gate.

Any change to the ruleset gets a corresponding update to `branch-protection.json` and a CHANGELOG entry under `### Changed`.

## Questions

Open a [Discussion](https://github.com/tigers1997/ClaudeCodeConfigurator/discussions) for general questions or a regular Issue for confirmed bugs/feature requests.
