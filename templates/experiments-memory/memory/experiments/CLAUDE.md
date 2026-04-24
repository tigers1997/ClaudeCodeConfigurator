# Experiments log

This directory holds a lazy-loaded record of hypotheses and their outcomes. This file is a nested CLAUDE.md — it injects into context only when Claude is reading files under `memory/experiments/`, so it costs nothing on a normal session.

## When to add an entry

Log an experiment when any of these are true:

- You set out to test a specific hypothesis ("X is faster than Y", "users prefer A over B", "migration N is safe on 50M rows").
- You tried something and it didn't work — negative results are at least as useful.
- Someone asks "why didn't we just do X?" and there's a real answer.

Don't log: micro-experiments during a single session, trial-and-error debugging, tentative refactors you then reverted mid-commit. Those belong in the commit message, not here.

## File format

One file per experiment: `YYYY-MM-DD-short-slug.md`.

Each file has these sections, in order:

```markdown
# <slug> — <one-line summary>

## Hypothesis
What you expected, as a falsifiable claim. One or two sentences.

## Setup
How you tested it. Links to the relevant PR, branch, notebook, or spec. Include a command to reproduce if it's mechanical.

## Result
What actually happened. Numbers if you have them. Screenshots / log snippets by reference, not pasted.

## Conclusion
Did the hypothesis hold? What changes? Link to the commit or doc that codifies the decision.

## Follow-ups
Anything you noticed on the side that's worth a later look. Bulleted.
```

## How this folder is used

- When you're about to do something that feels like "we've tried this before," ask Claude to search `memory/experiments/` first. Past results often rule out entire approaches in one line.
- When you finish an experiment, write the entry in a single commit. Don't let entries pile up in a feature branch — they're the kind of thing that vanishes in a squash merge.
- Entries are immutable once merged. If a later experiment overturns an earlier one, write a new entry that references the old one. Don't edit the old file.

## What Claude should do when reading this folder

Treat past experiments as evidence, not orders. If the user is asking for something a past experiment said doesn't work, surface the relevant file(s) and summarize — then ask whether conditions have changed. Don't silently refuse based on a stale result.
