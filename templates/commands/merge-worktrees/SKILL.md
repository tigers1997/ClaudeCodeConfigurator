---
name: merge-worktrees
description: Merge a set of worktree branches into the target branch safely. Creates a temp integration branch, merges each worktree in, runs tests, and only fast-forwards the target if everything passes. Use after running several parallel agents.
argument-hint: "[target-branch, default: main]"
allowed-tools: Read Bash(git worktree:*) Bash(git branch:*) Bash(git status) Bash(git log:*) Bash(git merge:*) Bash(git diff:*) Bash(git switch:*) Bash(git checkout:*) Bash(git push:*) Bash(git reset:*)
---

# Merge parallel worktree branches safely

Target branch: `$ARGUMENTS` (default: `main`)

## Context
- Current worktrees: !`git worktree list`
- Current branch: !`git branch --show-current`
- Target branch status: !`git log -1 --oneline ${ARGUMENTS:-main} 2>/dev/null || echo "target branch not found"`

## Workflow — don't skip steps

1. **Inventory.** List every worktree branch that should merge. Confirm with me before touching anything. If a worktree has uncommitted changes, stop and flag it — don't auto-stash.

2. **Create an integration branch.** From `$ARGUMENTS` (default `main`):
   ```
   git switch $ARGUMENTS
   git pull --ff-only
   git switch -c integrate/$(date +%Y%m%d-%H%M%S)
   ```

3. **Merge each worktree branch in, one at a time.** Use `--no-ff` so the merge is inspectable. If a merge conflicts, stop and show the conflict files. Do NOT auto-resolve — ask me.

4. **Run the project's verify loop on the integrated result.** Use the commands from `CLAUDE.md`'s "Commands" section (typecheck + lint + test). If any fail, stop and report. Do NOT try to fix in the integration branch — that defeats the point.

5. **If everything passes**, show me the summary:
   - Branches merged
   - Commits count
   - Diffstat
   - Any tests or checks that took noticeably longer

6. **Wait for approval before fast-forwarding `$ARGUMENTS`.** The fast-forward + push is a single-line script I can run after review — you should not push without explicit yes.

7. **After I approve and the push lands**, clean up:
   ```
   git worktree remove <each-worktree-path>
   git branch -d <each-merged-branch>
   git branch -D integrate/<timestamp>   # only after fast-forward lands on target
   ```
   Confirm each deletion — don't bulk-delete unreviewed.

## When to abort

- Any worktree has uncommitted or unpushed changes.
- Any merge conflicts. I'll resolve.
- Any verify step fails after merge. The integration branch is disposable; cut it and let me investigate the losing worktree in isolation.
- Any worktree's commit history looks wrong (force-pushed under you, rebased mid-session, etc.). Stop and show me the history.

## Notes

- If there are more than 5 worktrees, suggest batches of 3 instead of one giant integration. Easier to bisect failures.
- Worktree names are auto-generated slugs (`vigilant-feistel`, etc.) when spawned by Claude Code — don't assume a naming convention.
