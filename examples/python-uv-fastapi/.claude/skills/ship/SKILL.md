---
name: ship
description: Run the full pre-push gauntlet — format, lint, typecheck, test, commit, push. Confirms before each destructive step.
argument-hint: "[optional commit message override]"
allowed-tools: Bash(git:*) Bash(npm:*) Bash(pnpm:*) Bash(pytest:*) Bash(ruff:*) Bash(prettier:*) Bash(eslint:*) Bash(tsc:*) Read Grep
---

# Ship the current branch

Message override: $ARGUMENTS

## Checklist (stop at the first red step)

1. **Status** — `git status`. If detached HEAD or on `main`/`master`, stop.
2. **Format** — run the project's formatter on staged + changed files. Show what changed.
3. **Lint** — run the linter. If it fails, stop and ask how to proceed.
4. **Typecheck** — if the project uses one, run it.
5. **Test** — run fast tests relevant to the diff. If long-running tests exist, ask before running.
6. **Stage + commit** — use the `commit` skill's rules. If $ARGUMENTS was provided, use it as the summary.
7. **Pull with rebase** — `git pull --rebase` against the tracking branch. Resolve conflicts interactively with the user.
8. **Push** — confirm target branch, then `git push`. Never force-push without explicit approval.
9. **Open PR** — if `gh` is installed and the user wants one, run `gh pr create --fill --draft`.

After each step, print a one-line status. Stop the whole flow on any failure and show the last 30 lines of output.
