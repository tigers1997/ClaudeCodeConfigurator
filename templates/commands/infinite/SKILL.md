---
name: infinite
description: Generate N variations of a spec in parallel — each in its own subagent context, writing to its own output slot. Use for fanout work like "create 20 landing-page variants" or "draft 8 code-review subagent prompts." Not a general do-many-tasks button.
argument-hint: "<spec-file> <output-dir> <count-or-'infinite'>"
allowed-tools: Read Grep Glob Bash(ls:*) Bash(mkdir:*) Bash(test:*)
---

# Parallel spec expansion: `$ARGUMENTS`

Before anything touches disk, confirm **this is a parallelizable fanout task.** If the spec asks for sequential work, coupled features, or exploratory problem-solving, **refuse** and point at `.claude/rules/multi-agent-guardrails.md`. Parallel agents are a fanout multiplier, not a general speedup.

## Parse

The three positional args are: `spec_file`, `output_dir`, `count`.

- `spec_file` — the spec each subagent will read. Must exist.
- `output_dir` — where generated artifacts land. Each subagent writes to `output_dir/<iteration-slug>/`. Create if missing; don't clobber existing contents.
- `count` — integer ≥ 1, or the literal string `infinite`.

If any arg is missing or invalid, stop and show the correct usage.

## Phase 1 — Specification analysis

Read `spec_file` in full. Summarize in 3-5 bullets:
- What's the output shape? (a file? a component? a document?)
- What must be true of every output? (quality standards, schema constraints)
- What must VARY across outputs? (the uniqueness axis — style? approach? input data?)

If the spec is ambiguous on any of the above, ask **one** clarifying question and stop. Don't guess.

## Phase 2 — Output directory reconnaissance

`ls` the output dir. Note existing iteration slugs so new ones don't collide. If the dir has unrelated content, flag it and wait for approval before proceeding.

Build a **claimed-slots manifest** — a short structured note:
```
output_dir: <path>
existing_slugs: [slug-a, slug-b, ...]
next_slot_numbers: starting from <N>
unrelated_contents: <list or "none">
```

This manifest goes to every subagent and is the key anti-duplication trick.

## Phase 3 — Iteration strategy

Pick a batching plan based on `count`:

| count       | strategy                                                             |
|-------------|----------------------------------------------------------------------|
| 1-5         | Launch all subagents simultaneously in a single parallel Task call.  |
| 6-20        | Batches of 5. Launch batch, wait for all, then launch next.          |
| infinite    | Waves of 3-5. After each wave, check context usage; if > 50% start a fresh session and hand off the directory snapshot. Stop if user says stop. |

## Phase 4 — Parallel agent coordination

Dispatch subagents via the Task tool using the `parallel-generator` subagent. Each call's prompt must contain exactly these five sections (keep them labeled):

1. **spec_context** — the full contents of `spec_file` (or a summary if > 2k chars; include the path).
2. **claimed_slots_manifest** — the snapshot from Phase 2, updated with any slots claimed by earlier waves.
3. **iteration_assignment** — e.g. `iteration 7 of 20, slug: iter-07`.
4. **diversification_axis** — the axis this iteration should differ on, named explicitly. e.g. "this iteration must use a dark color palette"; "this iteration must favor imperative style over declarative."
5. **quality_standards** — the must-be-true bullets from Phase 1, verbatim.

**Do not ask subagents to coordinate with each other.** They cannot spawn their own subagents and their contexts don't share. The claimed_slots_manifest + diversification_axis does the coordination for them.

## After each wave

- Verify each subagent's claimed slot actually got written.
- If a subagent returned without producing a file, log the failure and continue — don't auto-retry (that's the user's call).
- Update the running directory snapshot with newly claimed slots before dispatching the next wave.

## When to abort mid-run

- User says stop.
- Context usage after a wave > 70% with more iterations to go (main context is for coordination, not content — start a fresh session).
- Three consecutive subagents return empty or broken output (the spec is probably wrong).
- Any subagent writes outside `output_dir` (a subagent misbehaving; stop and report).

## Report at the end

A table: iteration → slug → status (ok/failed) → one-line summary. Plus a count of successes and failures, and the path for the user to inspect.
