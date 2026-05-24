# discipline-skills — upstream sync notes (maintainer-internal)

This file is NOT shipped to users. It tracks the diff between this fork and the
upstream `obra/superpowers` plugin so we can keep them aligned over time.

## Source pin

- Upstream: https://github.com/obra/superpowers
- Last synced from: `claude-plugins-official` marketplace, **v5.1.0** (released 2026-05-04)
- License: MIT (see `LICENSE` in this directory)
- Copyright: © 2025 Jesse Vincent

## What we fork

Seven of the upstream's fourteen skills:

| Skill | File | Notes |
|---|---|---|
| brainstorming | `brainstorming/SKILL.md` | Visual-companion section + `brainstorming/scripts/` server stripped |
| writing-plans | `writing-plans/SKILL.md` | `superpowers:` prefix stripped from cross-references |
| executing-plans | `executing-plans/SKILL.md` | `superpowers:` prefix stripped from cross-references |
| verification-before-completion | `verification-before-completion/SKILL.md` | Verbatim |
| using-git-worktrees | `using-git-worktrees/SKILL.md` | Verbatim |
| subagent-driven-development | `subagent-driven-development/SKILL.md` | `superpowers:` prefix stripped; the `superpowers:requesting-code-review` Integration entry removed (template now embedded inline in `code-quality-reviewer-prompt.md`); the "Subagents should use superpowers:test-driven-development" companion line dropped |
| finishing-a-development-branch | `finishing-a-development-branch/SKILL.md` | Verbatim |

Supporting prompt templates carried over:
- `brainstorming/spec-document-reviewer-prompt.md` (verbatim)
- `writing-plans/plan-document-reviewer-prompt.md` (verbatim)
- `subagent-driven-development/implementer-prompt.md` (verbatim)
- `subagent-driven-development/spec-reviewer-prompt.md` (verbatim)
- `subagent-driven-development/code-quality-reviewer-prompt.md` (rewritten: the
  upstream version says "Use template at requesting-code-review/code-reviewer.md";
  we embed the full template content inline so the skill has no external dependency)

## What we don't fork

Seven upstream skills are intentionally excluded:

- `using-superpowers` — replaced by our slimmer `hooks/sessionstart-discipline.sh` bootstrap
- `dispatching-parallel-agents` — overlaps `multi-agent/dot-claude/rules/multi-agent-guardrails.md`
- `requesting-code-review` — overlaps configurator's `/review` skill + `code-reviewer` agent; the only place we needed its template (inside `subagent-driven-development`) has it embedded inline
- `receiving-code-review` — not surfaced today; reconsider in a later sync
- `systematic-debugging` — overlaps configurator's `/investigate` skill
- `test-driven-development` — TDD discipline is implicit in `writing-plans` task structure and `implementer-prompt.md`
- `writing-skills` — too meta for the configurator's default kit; skill authors install full superpowers

## Sync workflow

1. Watch `obra/superpowers` releases. Latest known: v5.1.0 (2026-05-04).
2. When a new release ships, diff each of the seven forked skills:
   ```bash
   SP=/home/bob/.claude/plugins/cache/claude-plugins-official/superpowers/<NEW_VERSION>/skills
   for s in brainstorming writing-plans executing-plans verification-before-completion using-git-worktrees subagent-driven-development finishing-a-development-branch; do
       diff -u templates/discipline-skills/$s/SKILL.md $SP/$s/SKILL.md
   done
   ```
3. For each meaningful upstream change, port the substance and re-apply the local edits documented above. Cosmetic edits (whitespace, anchor tweaks) skip.
4. Update the "Source pin" line at the top of this file with the new version + date.
5. Mention the bump in the release CHANGELOG entry.
6. Run `test/discipline-skills/` to confirm no regressions.

## Local edits — the canonical list

When porting a new upstream release, re-apply ALL of these:

1. **brainstorming/SKILL.md** — remove the entire `## Visual Companion` section (last section of the file). Drop the `Offer Visual Companion` step from the numbered checklist (item 2 in upstream's list). Drop the `Visual questions ahead?` diamond and the `Offer Visual Companion` box from the process-flow digraph.
2. **writing-plans/SKILL.md** — strip the `superpowers:` prefix from every cross-skill reference.
3. **executing-plans/SKILL.md** — strip the `superpowers:` prefix from every cross-skill reference. Reframe the "Tell your human partner that Superpowers works much better with access to subagents" line as a project-neutral capability note (the upstream says "Superpowers works much better"; we say "This skill works much better").
4. **subagent-driven-development/SKILL.md** — strip `superpowers:` prefix everywhere. In `## Integration → Required workflow skills`, REMOVE the `superpowers:requesting-code-review` line (template is embedded). REMOVE the entire `**Subagents should use:** superpowers:test-driven-development` block. Update the green-fill graphviz node `Use superpowers:finishing-a-development-branch` to `Use finishing-a-development-branch`.
5. **subagent-driven-development/code-quality-reviewer-prompt.md** — replace the `Use template at requesting-code-review/code-reviewer.md` reference with the full template content; append the four "In addition (subagent-driven-development specific)" bullets to the "What to Check" section.

## Why we forked rather than depending on the upstream plugin

See `docs/10-plugin-ecosystem.md` § "Discipline skills: bundled vs. upstream plugin" for the full rationale. Short version: ~930 tokens saved per session, curation control (we pick what ships), rugpull immunity (upstream removed three slash commands in v5.1.0 — bit us once already), and the configurator's existing module pipeline gives us a clean distribution path.
