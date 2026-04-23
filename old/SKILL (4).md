---
name: commit
description: Generate a Conventional Commit message from staged changes and commit. Asks before pushing.
allowed-tools: Bash(git:*)
---

# Smart commit

## Context
- Staged diff: !`git diff --staged`
- Unstaged diff (warn if present): !`git diff`
- Status: !`git status --short`

## Your task

1. If nothing is staged, stop and ask whether to `git add -A` or which files to stage.
2. Summarize the staged change in 1-2 sentences.
3. Pick a **Conventional Commit** type: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `style`.
4. Write the message in this format:
   ```
   <type>(<optional scope>): <imperative summary, <=72 chars>

   <body — WHY the change, not what. Wrap at 72 cols. Omit if summary is enough.>
   ```
5. Show the message and run `git commit -m "..."`. If the body is non-empty, use `-m "<summary>" -m "<body>"`.
6. After committing, show `git log -1 --stat` and **stop**. Do not push. Do not switch branches.

### Rules
- Never amend past commits unless asked.
- Never `--no-verify` unless the user explicitly tells you to.
- Keep one logical change per commit. If the diff spans multiple concerns, suggest splitting into `git add -p` first.
