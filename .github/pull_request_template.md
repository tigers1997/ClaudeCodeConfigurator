## What & why
<!-- 1-3 lines. What changes, and why. Reference issue # if any. -->

## Type of change
<!-- Pick one. Matches Conventional Commits prefix in your PR title. -->
- [ ] feat — new module / skill / feature (minor bump)
- [ ] fix — bug fix (patch bump)
- [ ] docs — documentation only
- [ ] chore — tooling, CI, release plumbing
- [ ] refactor — no behavioral change
- [ ] BREAKING — signaled via `!` suffix on the type (e.g. `feat!:`) or a `BREAKING CHANGE:` footer; invalidates `.claude-config.json` or rewrites template paths (major bump)

## Scope
- [ ] One logical change. (Multiple unrelated changes → separate PRs.)
- Modules affected: <!-- e.g. core, commands, multi-agent, mcp, ui, discipline-skills, git-workflow, safety, token-efficiency, experiments-memory, github-actions, recommend-plugins -->
- Personas affected: <!-- e.g. solo-newer, solo-experienced, small-team, library-author, custom; or "snapshot unchanged" -->

## Tests
- [ ] `python3 configure.py --check` passes locally.
- [ ] Added/updated fixtures under `test/` for new behavior.
- [ ] Persona snapshots (`examples/persona-*/expected-tree.txt`) updated if file layout changed.

## CHANGELOG
- [ ] Added an entry under `## Unreleased` in `CHANGELOG.md` using Keep-a-Changelog sections (`### Added` / `### Changed` / `### Fixed` / `### Removed` / `### Security`).
- [ ] I will SHA-anchor the entry after merge.

## License & NOTICE (load-bearing — read carefully)
- [ ] My contribution is my own work, or I have the right to submit it under the applicable license.
- [ ] No code under AGPL-3.0-incompatible licenses (proprietary, GPL-2-only, unknown).
- [ ] If I added third-party code anywhere: I added the corresponding entry to `NOTICE` and confirmed license compatibility.
- [ ] If I touched `templates/discipline-skills/`: the change is MIT-clean (no AGPL-only code pasted into that subtree).
- [ ] If I touched `LICENSE` or `NOTICE`: the maintainer is explicitly tagged for review.

## Signing
- [ ] All commits are signed (GPG or SSH).
- [ ] Conventional Commits prefix in PR title and commit messages.

## CLA
<!-- First-time contributors: cla-assistant will comment with a sign link.
     The license/cla status check stays red until you sign. No manual action
     needed beyond clicking the link. -->

## I understand
- [ ] An automated AI review will run on this PR. Blocking findings (`VERDICT: BLOCK`) will fail the `verdict-gate` check.
- [ ] No merge is possible while any required check is red, including for the maintainer.
- [ ] My contribution rights are described in `CONTRIBUTING.md` § "Your rights as a contributor".
