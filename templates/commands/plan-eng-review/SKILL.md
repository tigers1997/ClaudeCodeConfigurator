---
name: plan-eng-review
description: Engineering review of an existing plan before implementation begins. Surfaces hidden assumptions, traces data flow, generates a test matrix, and lists failure modes the plan glossed over. Output is structured Issues / Suggestions / Approved.
---

# /plan-eng-review

Engineering review of a written plan, before code is touched. Output is
the plan annotated with `[REVIEW]` notes plus a structured trailer
(Issues / Suggestions / Approved verdict).

## When to use this

- After `/plan` (or any other plan-author skill) produces a written plan
- Before approving a plan and entering implementation
- Mid-implementation when the plan starts feeling wrong

## Embedded patterns

include _patterns/confidence-gate.md
include _patterns/independent-verification.md

## Workflow

### 1. Read the plan top-to-bottom once

Don't take notes yet — just absorb the proposed shape. Get the gestalt
before nitpicking.

### 2. Surface hidden assumptions

For each step or component, ask: what does this assume that isn't
stated? Examples:

- "assumes the cache is empty at start"
- "assumes IDs are monotonic"
- "assumes a single writer"
- "assumes inputs are already validated upstream"

List every assumption you find. **Hidden assumptions are the most
common source of plan failure.** A plan with three explicit assumptions
is safer than a plan with zero — even if both are technically true,
because the explicit one survives a refactor of its surroundings.

### 3. Draw a text-form architecture diagram

Component → component, with the data that flows on each edge. Use
ASCII boxes or a simple `A → B → C` chain. If you can't draw it
clearly, the plan isn't precise enough — flag the gap.

### 4. State machines for non-trivial state

If any component has more than two states, write the state machine
explicitly: states, transitions, guards, terminal states. Implicit
state machines hide bugs.

### 5. Test matrix

For each component in the plan:

- What tests are proposed?
- What edge cases are covered?
- What edge cases are *not* covered?
- What integration boundaries lack tests?

A blank entry is a finding.

### 6. Failure modes

List every way each component could fail:

- Network unavailable
- Disk full / quota exceeded
- Race conditions / partial writes
- Malformed input
- Timeout
- Concurrent caller
- Partial failure (some sub-operations succeed)

For each, what's the recovery? "Crash" is not always wrong — but it
should be explicit and intentional.

### 7. Edge cases the plan glossed over

Common ones to look for:

- Empty input / single-element input / max-size input
- Concurrent operations
- Repeat operations (idempotency)
- Operations during shutdown
- Operations during initialization (before all dependencies ready)
- Unicode / encoding edge cases for text inputs

## Output shape

Annotate the plan inline with `[REVIEW]` notes. Then a structured
trailer:

```
## Issues (must address before proceeding)
1. <issue> — confidence: X/10
2. ...

## Suggestions (consider but not blocking)
1. <suggestion> — confidence: X/10
2. ...

## Approved
Yes/No. <one-line verdict>
```

Apply the **confidence gate** to each Issue and Suggestion. Drop anything
<7/10 rather than reporting it weakly. Apply **independent verification**
before listing each Issue: re-check the relevant code/spec from a
different angle; if the issue doesn't survive double-check, drop it.

## Anti-patterns this skill prevents

- Approving a plan because "it looks fine" without independent
  verification
- Listing issues without confidence ratings (every reader weights
  differently)
- Skipping the data-flow diagram because "it's obvious"
- Catching only happy-path test gaps
- Collecting too many low-confidence issues — confidence gate filters
  these out before they make the report

## Relationship to other skills

- **/plan** authors a plan; this skill reviews one. Different modes.
- **/investigate** is for bugs in code; this skill is for issues in
  plans. Both share the confidence-gate + independent-verification
  patterns.
- **/review** is post-code review; this skill is pre-code review.
