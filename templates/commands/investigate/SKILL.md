---
name: investigate
description: Systematic root-cause debugging for bugs, test failures, and unexpected behavior. Enforces the Iron Law (no fix without investigation). Writes findings to .claude/investigations/ before any code change.
---

# /investigate

Systematic root-cause debugging. The Iron Law: no code change is
proposed without an investigation phase that produces a written
hypothesis + observations + conclusion.

## When to use this

- A test is failing and you don't yet understand why
- Behavior in production differs from what the code seems to do
- You're about to "fix" something but haven't traced the data flow
- A previous fix didn't work and you're tempted to try another

## Embedded patterns

include _patterns/no-fix-without-investigation.md
include _patterns/confidence-gate.md
include _patterns/independent-verification.md

## Workflow

### 1. State the symptom in one line

What is observed? Not "what's wrong" — what's *seen*. A single sentence,
written before any code is read.

### 2. Form a hypothesis before reading any code

Write the hypothesis down. The hypothesis is your prior; you're going
to update it with evidence. Forming it first prevents the common
failure mode where evidence gets cherry-picked to fit whatever theory
emerges from reading.

### 3. Trace the data flow

Pick one entry point (a failing test, a request handler, a CLI
invocation) and walk every transformation the data undergoes. At each
step:

- Predict the next value based on your hypothesis.
- Read the code or run the call to observe the actual value.
- If your prediction is wrong, you've found a divergence point — that's
  the lead.

Don't skim. Don't guess. Trace.

### 4. Run a test that would fail if your hypothesis is correct

If your hypothesis says "function X returns null on edge case Y," call
X with Y and observe. The hypothesis must be falsifiable. If you can't
write a test that distinguishes hypothesis-true from hypothesis-false,
you don't have a hypothesis — you have a vibe.

### 5. Write findings before any code change

Save findings to `.claude/investigations/<topic>-<date>.md` in this
exact shape:

```
# Symptom
<one line>

# Hypothesis (initial)
<what you suspected>

# Observations
- <each trace step + observed value>
- ...

# Conclusion
<root cause, with the evidence that supports it>

# Next-step
<code change to propose, OR "do nothing" if the bug isn't what was reported>
```

### 6. The 3-failed-fix stop

If three attempted fixes fail in a row, halt. Re-read your findings; if
the conclusion was wrong, the fix attempts have been doing more harm
than good. **Restart investigation from step 1.** Do not attempt a
fourth fix without re-investigating.

## Output

- A findings doc at `.claude/investigations/<topic>-<date>.md`
- A terse chat summary: "Root cause: <one line>. Proposed fix: <one line> (confidence: X/10)."
- **No code change is made by this skill itself** — it stops at the
  proposed-fix step. The user (or `/review`/`/plan`) takes it from
  there.

## Anti-patterns this skill prevents

- Proposing a fix without running the failing test once
- "It might be in the cache layer" with no trace evidence
- Repeatedly tweaking the symptom location until the test passes (vs.
  understanding the cause)
- Confidence-laundering: dressing up a guess as a finding
- Skipping the hypothesis step because "the code is obvious"

## Relationship to other skills

- **/plan** authors a plan; this skill investigates a bug. Different
  modes.
- **/review** flags issues but does not investigate them — when
  /review surfaces a bug, the right next step is `/investigate`.
- **/plan-eng-review** validates a plan; this skill validates a bug
  report. Both apply confidence gates and independent verification.
