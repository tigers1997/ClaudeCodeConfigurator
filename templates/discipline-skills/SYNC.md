# discipline-skills — upstream sync notes (maintainer-internal)

This file is NOT shipped to users. It tracks the diff between this fork and the
upstream `obra/superpowers` plugin so we can keep them aligned over time.

## Source pin

- Upstream: https://github.com/obra/superpowers
- Last synced from: tag **v6.3.0** (released 2026-08-12; `claude-plugins-official`
  marketplace entry pins the same commit, `b36e0829`)
- License: MIT (see `LICENSE` in this directory)
- Copyright: © 2025 Jesse Vincent

**v6.0.2 → v6.3.0 sync notes (2026-08-24).** Four upstream releases since the last
sync, all landing in the seven forked skills:

- **v6.0.3 (2026-06-18)** — SDD scratch files moved out of `.git/` (Claude Code
  denies agent writes there) into a self-ignoring `.superpowers/sdd/` working-tree
  directory resolved by a new shared script, `scripts/sdd-workspace`; `task-brief`
  and `review-package` now call it instead of `git rev-parse --git-path sdd`.
- **v6.1.0 / v6.1.1 (2026-06-30 / 07-02)** — `using-superpowers` bootstrap compressed,
  per-harness tool references pruned, Codex packaging. No content change in the
  seven forked skills; the bootstrap is a skill we replace with our own hook anyway.
- **v6.2.0 (2026-07-24)** — the big one. SDD's workspace is now **plan-scoped**
  (`.superpowers/sdd/<plan-basename>/`; `review-package` gained the plan file as its
  first argument: `review-package PLAN_FILE BASE HEAD`); the review-fix loop resumes
  the implementer instead of dispatching fresh, gets a scoped re-review prompt
  (`re-review-prompt.md`, NEW) and a five-round circuit breaker; SKILL.md is
  reorganized by lifecycle. A library-wide **compression campaign** removed the
  Bottom Line / Key Principles / Advantages / Integration / "Why This Matters"
  sections from `brainstorming`, `verification-before-completion`, `executing-plans`,
  `subagent-driven-development`, `using-git-worktrees` and `writing-plans`, folding
  the load-bearing arguments into Excuse/Reality rationalization tables.
  `finishing-a-development-branch` no longer offers "Discard this work" in its menu
  (discard survives only as an explicit-request path), creates PRs with whichever
  forge tooling is present, and fixes a real bug (worktree path captured before the
  cleanup `cd`). Upstream's SessionStart hook also gained `"shell": "bash"` for
  Windows (CC ≥ 2.1.81 resolves Git Bash directly instead of falling back to
  PowerShell) — the configurator adopted that key on **every** shipped command hook
  in the same release as this sync.
- **v6.3.0 (2026-08-12)** — `brainstorming` now classifies each request as
  **spike / bounded / architectural** and scales the ceremony (only the
  architectural path writes a spec and hands off to `writing-plans`; the approval
  gate never scales). SDD controllers issue recorded **rulings** instead of stalling
  on plan conflicts, the pre-flight conflict scan is written to the ledger as a
  table, small same-shape tasks batch into one dispatch, implementers and reviewers
  are forbidden from spawning their own subagents (duplicate review seats), plans
  carry a `**Spec:**` pointer (`writing-plans` header), and reviewers re-read
  illegible evidence instead of re-running suites. `finishing-a-development-branch`
  stops and asks when `git worktree remove` refuses because of untracked files
  (never `--force` on its own).

Skill inventory unchanged (14/14 upstream; we still fork the same 7). Two files
added to the module's `paths:` (`re-review-prompt.md`, `scripts/sdd-workspace`),
15 → 17 paths.

## What we fork

Seven of the upstream's fourteen skills:

| Skill | File | Notes |
|---|---|---|
| brainstorming | `brainstorming/SKILL.md` | `## Visual Companion` section stripped + the "Offer the visual companion just-in-time" step dropped from the **Architectural** checklist (renumbered to 8 items; the Spike and Bounded lists are untouched). `visual-companion.md` and `scripts/` excluded from the module's `paths:` (we don't ship the browser server) |
| writing-plans | `writing-plans/SKILL.md` | `superpowers:` prefix stripped from cross-references (5 sites in v6.3.0) |
| executing-plans | `executing-plans/SKILL.md` | `superpowers:` prefix stripped + the "Tell your human partner that Superpowers works much better…" note reframed as a project-neutral capability note without the harness list or the `../using-superpowers/references/` pointer (we don't ship `using-superpowers`). v6.2.0 dropped the upstream `## Integration` section, so nothing else is local |
| verification-before-completion | `verification-before-completion/SKILL.md` | Verbatim |
| using-git-worktrees | `using-git-worktrees/SKILL.md` | Verbatim |
| subagent-driven-development | `subagent-driven-development/SKILL.md` | `superpowers:` prefix stripped (6 sites, including the graphviz green-fill node `"Use finishing-a-development-branch"`). The **final whole-branch review** is pointed at the configurator's `code-reviewer` subagent instead of upstream's `../requesting-code-review/code-reviewer.md` (a skill we don't ship): three digraph node labels become `"Dispatch final code reviewer (code-reviewer subagent)"` and the `## Final Review` paragraph names `.claude/agents/code-reviewer.md` with a `task-reviewer-prompt.md` fallback when the `commands` module isn't installed. This resolves the papercut carried since v5.1.0. v6.2.0 dropped the upstream `## Integration` section, so the former "remove the requesting-code-review / test-driven-development lines" edits are obsolete |
| finishing-a-development-branch | `finishing-a-development-branch/SKILL.md` | Verbatim |

Supporting prompt templates carried over:
- `brainstorming/spec-document-reviewer-prompt.md` (verbatim)
- `writing-plans/plan-document-reviewer-prompt.md` (verbatim)
- `subagent-driven-development/implementer-prompt.md` (verbatim — v6.3.0 adds the
  "You Do Not Dispatch Subagents" contract and the resume-on-findings fix flow)
- `subagent-driven-development/task-reviewer-prompt.md` (verbatim — v6.3.0 adds the
  no-subagents contract, batched-brief file-by-file checking, and the
  "evidence you cannot see is not evidence that doesn't exist" rule)
- `subagent-driven-development/re-review-prompt.md` (verbatim — NEW in v6.2.0; the
  scoped re-review used by every fix round)

Supporting scripts carried over (all bash, executable, no `.sh` extension —
matching upstream):
- `subagent-driven-development/scripts/sdd-workspace` (NEW in v6.0.3; resolves and
  creates `<repo-root>/.superpowers/sdd/<plan-basename>/`, writing the self-ignoring
  `.gitignore`)
- `subagent-driven-development/scripts/review-package` (signature changed in
  v6.2.0: `PLAN_FILE BASE HEAD [OUTFILE]`)
- `subagent-driven-development/scripts/task-brief`

The configurator's exec-bit heuristic honors the source file's user-execute bit,
so the scripts arrive at user installs with `+x`. On a Windows checkout
(`core.filemode=false`) a new script's index mode must be set explicitly —
`git add --chmod=+x <path>` — or it lands in the repo as `100644`.

## What we don't fork

Seven upstream skills are intentionally excluded:

- `using-superpowers` — replaced by our slimmer `hooks/sessionstart-discipline.sh` bootstrap
- `dispatching-parallel-agents` — overlaps `multi-agent/dot-claude/rules/multi-agent-guardrails.md`
- `requesting-code-review` — overlaps the configurator's `/review` skill + `code-reviewer` agent. The one upstream reference to it (SDD's final whole-branch review) is rewritten to use that agent — see the table above; no broken link remains
- `receiving-code-review` — not surfaced today; reconsider in a later sync
- `systematic-debugging` — overlaps the configurator's `/investigate` skill
- `test-driven-development` — TDD discipline is implicit in `writing-plans` task structure and `implementer-prompt.md`'s RED/GREEN evidence format (v6.2.0 renamed its reference doc to `writing-good-tests.md`; still not shipped)
- `writing-skills` — too meta for the configurator's default kit; skill authors install full superpowers

Also explicitly excluded at the file level (subdirectories of forked skills we don't carry):

- `brainstorming/visual-companion.md` — the browser-companion long-form guide; we ship a slimmer SKILL.md with the entire `## Visual Companion` section removed
- `brainstorming/scripts/` — the visual companion's Node server (`server.cjs`, `helper.js`, `frame-template.html`, `start-server.sh`, `stop-server.sh`); we don't ship a browser companion at all

## Sync workflow

1. Watch `obra/superpowers` releases. Latest known: **v6.3.0 (2026-08-12)**.
2. When a new release ships, diff each of the seven forked skills. Either point at
   the plugin cache (`~/.claude/plugins/cache/<marketplace>/superpowers/<VERSION>/skills`)
   or clone the tag:
   ```bash
   git clone --depth 1 --branch v<NEW_VERSION> https://github.com/obra/superpowers.git /tmp/sp
   SP=/tmp/sp/skills
   for s in brainstorming writing-plans executing-plans verification-before-completion using-git-worktrees subagent-driven-development finishing-a-development-branch; do
       diff -ur templates/discipline-skills/$s $SP/$s
   done
   ```
   On a Windows checkout with `core.autocrlf=true`, textually identical files diff
   as whole-file changes (CRLF vs LF) — compare with `diff --strip-trailing-cr`
   before treating a file as changed.
3. For each meaningful upstream change, port the substance and re-apply the local edits documented below. Cosmetic edits (whitespace, anchor tweaks) skip.
4. **File-list change check.** If an upstream skill gained/lost files (v5→v6 dropped two reviewer prompts and added `task-reviewer-prompt.md` + `scripts/`; v6.0.3 added `scripts/sdd-workspace`; v6.2.0 added `re-review-prompt.md`), update **both** the `paths:` list in `config_schema.py` (discipline-skills module) and the table above, plus `test/discipline-skills/test-module-files-exist.sh` and `test-scaffold-installs-skills.sh`, then regenerate the persona `expected-tree.txt` fixtures.
5. **Exec-bit check.** If new scripts ship without a `.sh` extension, confirm they have exec bits in the upstream tree (`ls -l`), that the configurator's `executable` heuristic (`configure.py`, the two `collect_files` call sites) still picks them up, and that the git index mode is `100755` (`git ls-files -s`).
6. Update the "Source pin" line at the top of this file with the new version + date, and add a brief delta paragraph.
7. Mention the bump in the release CHANGELOG entry.
8. Run `test/discipline-skills/` to confirm no regressions (especially `test-no-superpowers-prefix.sh` and `test-module-files-exist.sh`).

## Local edits — the canonical list

When porting a new upstream release, re-apply ALL of these. The fast path is
`sed -i 's/superpowers://g'` over the three SKILL.md files that carry the prefix,
plus the targeted edits in items 1, 3, and 4 below. Verify with a grep over every
shipped file for `superpowers:`, `requesting-code-review`, `using-superpowers`,
`test-driven-development`, and `visual-companion` / `Visual Companion` — all five
must come back empty.

1. **brainstorming/SKILL.md** — remove the entire `## Visual Companion` section (last section of the file). In the `## Checklist`, drop the `Offer the visual companion just-in-time` step from the **Architectural** list (item 2 in upstream's v6.3.0 list) and renumber the rest (9 → 8 items). The Spike and Bounded lists have no visual-companion step. The process-flow digraph carries no visual-companion nodes.
2. **writing-plans/SKILL.md** — strip the `superpowers:` prefix from every cross-skill reference.
3. **executing-plans/SKILL.md** — strip the `superpowers:` prefix from every cross-skill reference. Replace the whole `**Note:** Tell your human partner that Superpowers works much better…` sentence with: *"**Note:** This skill works much better with access to subagents. The quality of its work will be significantly higher when run on Claude Code (the platform this configurator targets). If subagents are available, use subagent-driven-development instead of this skill."* (drops the harness list and the `../using-superpowers/references/` pointer).
4. **subagent-driven-development/SKILL.md** — strip `superpowers:` everywhere (this also rewrites the graphviz green-fill node to `"Use finishing-a-development-branch"`). Then point the final whole-branch review at the configurator's agent: replace every `"Dispatch final code reviewer (../requesting-code-review/code-reviewer.md)"` node label (3 sites: declaration + two edges) with `"Dispatch final code reviewer (code-reviewer subagent)"`, and in `## Final Review` replace *"using requesting-code-review's [code-reviewer.md](../requesting-code-review/code-reviewer.md)."* with *"using this project's `code-reviewer` subagent (`.claude/agents/code-reviewer.md`, shipped by the configurator's `commands` module; if it isn't installed, dispatch a general-purpose subagent with [task-reviewer-prompt.md](task-reviewer-prompt.md) scoped to the whole branch)."*

Retired edits (kept for archaeology): the v5-era "embed `code-reviewer.md` inline in `code-quality-reviewer-prompt.md`" rewrite (file gone since v6.0.0) and the v6.0.x "remove the `requesting-code-review` / `Subagents should use: test-driven-development` lines from `## Integration`" edits (section gone since v6.2.0). If a future upstream re-introduces either, revisit.

## Why we forked rather than depending on the upstream plugin

See `docs/10-plugin-ecosystem.md` § "Discipline skills: bundled vs. upstream plugin" for the full rationale. Short version: ~930 tokens saved per session, curation control (we pick what ships), rugpull immunity (upstream removed three slash commands in v5.1.0 — bit us once already), and the configurator's existing module pipeline gives us a clean distribution path. The v6.x multi-harness expansion (Codex, Copilot, Cursor, Pi, Hermes, Devin, Antigravity) widens the gap between "what we ship" and "what the full plugin offers" — users wanting cross-harness support should install the upstream plugin; users on Claude Code who want a smaller, curated kit use ours.
