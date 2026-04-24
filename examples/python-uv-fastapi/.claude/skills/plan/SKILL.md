---
name: plan
description: Produce a structured implementation plan before any code changes. Use when a task touches more than one file or involves non-trivial design.
argument-hint: "[brief description of what to plan]"
allowed-tools: Read Grep Glob Bash(git status) Bash(git diff:*) Bash(ls:*) Bash(find:*)
context: fork
agent: Plan
---

# Plan a change: $ARGUMENTS

Produce a plan, **do not edit code**. Output in this exact structure:

## Goal
One sentence. What does "done" look like?

## Assumptions
Bullet list of every assumption you're making about intent, scope, and environment. Flag any that you're unsure about with ⚠️.

## Relevant files
For each file that matters, give `path:line-range` and one line on why it matters. Pull from `git status` and targeted searches — don't read irrelevant files.

## Approach
Numbered steps. Each step is one logical change, the smallest possible. Call out whether it's additive, modifying, or deleting.

## Risk & rollback
- What could break?
- How will you detect it (tests, manual check)?
- How do you back out if the change is wrong?

## Open questions
List anything you need the user to confirm before implementing. **If any exist, stop here and ask.**

## Estimated diff size
Rough count of files and lines. Flag anything over 200 LOC — it should probably be split.
