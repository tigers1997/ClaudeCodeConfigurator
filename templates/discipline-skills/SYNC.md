# discipline-skills — upstream sync notes (maintainer-internal)

This file is NOT shipped to users. It tracks the diff between this fork and the
upstream `obra/superpowers` plugin so we can keep them aligned over time.

## Source pin

- Upstream: https://github.com/obra/superpowers
- Last synced from: `claude-plugins-official` marketplace, **v6.0.2** (released 2026-06-17)
- License: MIT (see `LICENSE` in this directory)
- Copyright: © 2025 Jesse Vincent

**v5.1.0 → v6.0.2 sync notes (2026-06-17).** Upstream's v6.0.0 was a major release: per-task reviewer prompts unified into one (`task-reviewer-prompt.md` replaces both `spec-reviewer-prompt.md` and `code-quality-reviewer-prompt.md`); two new bash scripts (`scripts/review-package` + `scripts/task-brief`) move diff and task text to files so they don't park permanently in the controller's context; the legacy global worktree directory (`~/.config/superpowers/worktrees/`) was dropped in favor of project-local `.worktrees/`; `writing-plans` gained Global Constraints + per-task Interfaces blocks; brainstorming's visual companion was rewritten with a real security model (we still strip it entirely); and prose across all skills moved from "Claude / Task tool" to "your agent / dispatch a subagent" so the skills work cross-harness (Claude Code, Codex, Copilot, Gemini, Pi, Antigravity). Our SYNC.md "embed code-reviewer.md inline in code-quality-reviewer-prompt.md" rewrite (v5.1.0 era) is RETIRED — the file no longer exists upstream and the unified `task-reviewer-prompt.md` has no external dependency. v6.0.1 and v6.0.2 are bug-fix releases on top of v6.0.0 (Codex bootstrap fixes, eval-submodule cleanup) with no impact on the 7 forked skills.

## What we fork

Seven of the upstream's fourteen skills:

| Skill | File | Notes |
|---|---|---|
| brainstorming | `brainstorming/SKILL.md` | Visual companion checklist item dropped + `## Visual Companion` section stripped + `visual-companion.md` and `scripts/` excluded from the module's `paths:` (we don't ship the browser server) |
| writing-plans | `writing-plans/SKILL.md` | `superpowers:` prefix stripped from cross-references |
| executing-plans | `executing-plans/SKILL.md` | `superpowers:` prefix stripped + the "Superpowers works much better with access to subagents" line reframed as project-neutral capability note; the parenthetical pointer to `../using-superpowers/references/` was dropped (we don't ship `using-superpowers`) |
| verification-before-completion | `verification-before-completion/SKILL.md` | Verbatim |
| using-git-worktrees | `using-git-worktrees/SKILL.md` | Verbatim (v6.0.0 dropped the global `~/.config/superpowers/worktrees/` path; our fork inherits this stricter project-local convention cleanly) |
| subagent-driven-development | `subagent-driven-development/SKILL.md` | `superpowers:` prefix stripped (including the graphviz `Use superpowers:finishing-a-development-branch` green-fill node); the Integration section's `**requesting-code-review** - Code review template for the final whole-branch review` line REMOVED (we don't ship that skill); the entire `**Subagents should use:** test-driven-development` block REMOVED |
| finishing-a-development-branch | `finishing-a-development-branch/SKILL.md` | Verbatim (v6.0.0 also drops the global worktree path here; the v6.0.0 "forge-neutral" rewrite that drops hardcoded `gh pr create` is inherited cleanly) |

Supporting prompt templates carried over:
- `brainstorming/spec-document-reviewer-prompt.md` (verbatim)
- `writing-plans/plan-document-reviewer-prompt.md` (verbatim)
- `subagent-driven-development/implementer-prompt.md` (verbatim — v6.0.0 rewrote it to read task-brief from file, require explicit `model:` field, and add RED/GREEN TDD evidence format; the rewrite is inherited as-is, no local edits)
- `subagent-driven-development/task-reviewer-prompt.md` (verbatim — NEW in v6.0.0, replaces the v5 split spec-reviewer + code-quality-reviewer files; no external dependency on `requesting-code-review`)

Supporting scripts carried over (NEW in v6.0.0):
- `subagent-driven-development/scripts/review-package` (bash, executable; writes review diff package to a file the reviewer reads in one call)
- `subagent-driven-development/scripts/task-brief` (bash, executable; extracts one task's full text from a plan into a file the implementer reads in one call)

Both scripts ship without a `.sh` extension (matching upstream); the configurator's exec-bit heuristic was widened in this sync to also honor the source file's user-execute bit, so the scripts arrive at user installs with `+x` set.

## What we don't fork

Seven upstream skills are intentionally excluded:

- `using-superpowers` — replaced by our slimmer `hooks/sessionstart-discipline.sh` bootstrap
- `dispatching-parallel-agents` — overlaps `multi-agent/dot-claude/rules/multi-agent-guardrails.md`
- `requesting-code-review` — overlaps configurator's `/review` skill + `code-reviewer` agent. **Known papercut**: `subagent-driven-development/SKILL.md` still has one "final whole-branch review" line (around line 268 post-v6 port) that references `../requesting-code-review/code-reviewer.md`; that link is broken in our fork (always was). Not addressed in this sync to keep the port scope tight; revisit if it surfaces in user reports.
- `receiving-code-review` — not surfaced today; reconsider in a later sync
- `systematic-debugging` — overlaps configurator's `/investigate` skill (and v6.0.0's "no longer trips extended-thinking" fix doesn't change the overlap)
- `test-driven-development` — TDD discipline is implicit in `writing-plans` task structure and `implementer-prompt.md`'s RED/GREEN evidence format (the latter is now v6-explicit)
- `writing-skills` — too meta for the configurator's default kit; skill authors install full superpowers

Also explicitly excluded at the file level (subdirectories of forked skills we don't carry):

- `brainstorming/visual-companion.md` — the browser-companion long-form guide; we ship a slimmer SKILL.md with the entire `## Visual Companion` section removed
- `brainstorming/scripts/` — the visual companion's Node server (`server.cjs`, `helper.js`, `frame-template.html`, `start-server.sh`, `stop-server.sh`); we don't ship a browser companion at all

## Sync workflow

1. Watch `obra/superpowers` releases. Latest known: **v6.0.2 (2026-06-17)**.
2. When a new release ships, diff each of the seven forked skills:
   ```bash
   SP=/home/bob/.claude/plugins/cache/claude-plugins-official/superpowers/<NEW_VERSION>/skills
   for s in brainstorming writing-plans executing-plans verification-before-completion using-git-worktrees subagent-driven-development finishing-a-development-branch; do
       diff -ur templates/discipline-skills/$s $SP/$s
   done
   ```
3. For each meaningful upstream change, port the substance and re-apply the local edits documented below. Cosmetic edits (whitespace, anchor tweaks) skip.
4. **File-list change check.** If an upstream skill gained/lost files (e.g. v5→v6 dropped the two reviewer prompts and added `task-reviewer-prompt.md` + `scripts/`), update **both** the `paths:` list in `config_schema.py` (discipline-skills module) and the table above.
5. **Exec-bit check.** If new scripts ship without a `.sh` extension (like v6's `review-package` / `task-brief`), confirm they have exec bits in the upstream cache (`ls -l`), and verify the configurator's `executable` heuristic (`configure.py` around lines 1779 / 1799) still picks them up — the current rule honors `.sh`-suffix OR source-file user-execute bit.
6. Update the "Source pin" line at the top of this file with the new version + date, and add a brief delta paragraph.
7. Mention the bump in the release CHANGELOG entry.
8. Run `test/discipline-skills/` to confirm no regressions (especially `test-no-superpowers-prefix.sh` and `test-module-files-exist.sh`).

## Local edits — the canonical list

When porting a new upstream release, re-apply ALL of these. The fast path is `sed -i 's/superpowers://g' …` over the three SKILL.md files that carry the prefix, plus the targeted Edits in items 1, 2, and 5 below.

1. **brainstorming/SKILL.md** — remove the entire `## Visual Companion` section (last section of the file). Drop the `Offer the visual companion just-in-time` step from the numbered checklist (item 2 in upstream's list) and renumber the rest. The process-flow digraph in v6.0.2 no longer contains visual-companion nodes (upstream removed them), so the v5-era digraph edits are obsolete.
2. **writing-plans/SKILL.md** — strip the `superpowers:` prefix from every cross-skill reference.
3. **executing-plans/SKILL.md** — strip the `superpowers:` prefix from every cross-skill reference. Reframe the "Tell your human partner that Superpowers works much better" line as a project-neutral capability note (upstream says "Superpowers works much better"; we say "This skill works much better") and drop the parenthetical pointer to `../using-superpowers/references/` (we don't ship `using-superpowers`).
4. **subagent-driven-development/SKILL.md** — strip `superpowers:` prefix everywhere (this also handles the graphviz green-fill node update from `"Use superpowers:finishing-a-development-branch"` to `"Use finishing-a-development-branch"`). In `## Integration → Required workflow skills`, REMOVE the `**requesting-code-review** - Code review template for the final whole-branch review` line (we don't ship that skill). REMOVE the entire `**Subagents should use:** test-driven-development` block (4 lines).
5. **No more reviewer-prompt embedding.** Pre-v6 the canonical edit list had a fifth item: rewrite `code-quality-reviewer-prompt.md` to embed `requesting-code-review/code-reviewer.md` inline. That edit is RETIRED — v6.0.0 unified the two reviewer prompts into `task-reviewer-prompt.md` (which has no external dependency), and the original `code-quality-reviewer-prompt.md` file is gone. If a future upstream re-introduces split reviewers, revisit.

## Why we forked rather than depending on the upstream plugin

See `docs/10-plugin-ecosystem.md` § "Discipline skills: bundled vs. upstream plugin" for the full rationale. Short version: ~930 tokens saved per session, curation control (we pick what ships), rugpull immunity (upstream removed three slash commands in v5.1.0 — bit us once already), and the configurator's existing module pipeline gives us a clean distribution path. The v6.0.0 multi-harness expansion (Codex, Copilot, Pi, Antigravity) widens the gap between "what we ship" and "what the full plugin offers" — users wanting cross-harness support should install the upstream plugin; users on Claude Code who want a smaller, curated kit use ours.
