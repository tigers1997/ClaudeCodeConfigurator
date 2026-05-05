---
name: review
description: Code-review the current branch's changes against main. Use before committing or pushing.
argument-hint: "[optional focus area]"
allowed-tools: Read Grep Glob Bash(git diff:*) Bash(git log:*) Bash(git status)
context: fork
agent: code-reviewer
---

# Review changes

Focus: $ARGUMENTS (if empty, review everything changed on the current branch)

## Context
- Branch vs main diff: !`git diff --merge-base main -- . ':(exclude)*.lock' ':(exclude)package-lock.json' ':(exclude)pnpm-lock.yaml'`
- Files changed: !`git diff --merge-base main --name-status`
- Last 5 commits: !`git log --oneline -n 5`

## Embedded patterns

include _patterns/confidence-gate.md
include _patterns/independent-verification.md
include _patterns/ai-slop-detection.md

## Your task

Act as a senior reviewer on a pull request. Produce:

### Verdict
One of: **Ship it**, **Ship with nits**, **Needs changes**.

### Critical issues (must fix)
Security bugs, correctness bugs, broken contracts, missing tests for new logic. Apply the **confidence gate** (≥7) — drop low-confidence findings rather than reporting them weakly.

### Warnings (should fix)
Readability, naming, duplication, missing types, insufficient error handling. Same confidence gate.

### Suggestions (nice-to-haves)
Design improvements, simpler alternatives, refactor opportunities.

### What's good
Call out at least one thing that was done well. Reinforces the pattern.

For each issue, cite `file:line` and give a concrete fix or code snippet. Apply **independent verification** — re-read the relevant code path before reporting; drop findings that don't survive a second look.

### `[ AUTO-FIXED ]`
For obvious, low-risk issues (typos, formatting drift, unused imports), apply the fix atomically and report under `[ AUTO-FIXED ]` as a one-line summary per fix:

```
[ AUTO-FIXED ]
  src/api.py:42  fixed typo: "recieve" → "receive"
  src/db.py:103  removed unused import
```

Don't list these as findings — they're already done.

### `[ ASK ]`
For findings with ambiguity or judgment calls, surface them as questions in `[ ASK ]`:

```
[ ASK ]
  src/auth.py:55  Should we use bcrypt or argon2 here? The plan didn't specify.
```

Use `AskUserQuestion` to actually prompt; the `[ ASK ]` summary is for the report.

### `[ SLOP ]`
Run the AI-slop checklist (see embedded pattern above) over the diff. Report matches in `[ SLOP ]`:

```
[ SLOP ]
  src/api.py:12  filler: "It is important to note"
```

Empty when clean.

### `[ COMPLETENESS ]`
For each requirement stated in the PR/commit message, verify the change actually implements it. Report any gaps:

```
[ COMPLETENESS ]
  PR description mentions "rate limiting" — no rate-limiting code found in the diff.
```

### When you find a bug

**Don't fix in place.** Note "Run /investigate before proposing a fix" in the report. The Iron Law (see `/investigate`) says no fix without investigation; `/review`'s job is to flag, not to debug.
