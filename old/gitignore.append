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

## Your task

Act as a senior reviewer on a pull request. Produce:

### Verdict
One of: **Ship it**, **Ship with nits**, **Needs changes**.

### Critical issues (must fix)
Security bugs, correctness bugs, broken contracts, missing tests for new logic.

### Warnings (should fix)
Readability, naming, duplication, missing types, insufficient error handling.

### Suggestions (nice-to-haves)
Design improvements, simpler alternatives, refactor opportunities.

### What's good
Call out at least one thing that was done well. Reinforces the pattern.

For each issue, cite `file:line` and give a concrete fix or code snippet.
