---
name: session-retro
description: End-of-session retro. Diff what actually happened in this session against CLAUDE.md / rules and propose updates to capture anything worth remembering. Run before closing a long session.
allowed-tools: Read Grep Glob
---

# Session retrospective

You have just finished a real working session. Don't ask me what happened — read the transcript and figure it out.

## Your task

1. **Review this session.** Look at the tasks completed, the files you edited, the commands you ran, and any surprises or course-corrections. Focus on what *changed your understanding* of the project — traps you hit, conventions you discovered, quirks in tools or environment, decisions that got made.

2. **Read current documentation.** Load `CLAUDE.md` and every `.claude/rules/*.md`. Know what's already captured before suggesting additions.

3. **Propose updates, per file.** For each thing worth remembering, say where it belongs:
   - **`CLAUDE.md`** — applies project-wide, short enough to earn its line. Must survive the 200-line soft cap.
   - **`.claude/rules/<scope>.md`** — path-scoped. Create a new rules file with a `paths:` frontmatter glob if the rule is only relevant to certain directories.
   - **Tool-calling guardrails** (in CLAUDE.md's "Working with Claude" section) — if you kept hitting a specific model quirk this session (e.g., "forgot to activate venv," "ran wrong test command"), fill in one of those bullet slots.
   - **Nothing** — say so. Not every session produces a docs update, and forcing one dilutes the signal.

4. **Show the diff, don't write it.** Output each proposed change as a before/after pair. Wait for approval before touching files. If approved, apply the edits in one pass.

## What counts as "worth remembering"

- A command or script that wasn't obvious to discover.
- A gotcha hit during debugging that took more than 5 minutes to resolve.
- A convention (naming, structure, error-handling) now visible in 2+ files.
- A dependency or integration added in this session.
- An architectural decision with rationale — the *why*, not just the *what*.

## What to skip

- Individual file-by-file summaries of what you did. That's what `git log` and the transcript are for.
- Restating conventions already in `CLAUDE.md`.
- Speculation about future work that wasn't validated this session.
- Motherhood statements ("write clean code", "test thoroughly").

## Finish by

Proposing one **process retrospective** bullet: one thing that would have made this session smoother. A missing tool, a confusing default, a redundant step. This is meta-feedback for the human, not a file edit.
