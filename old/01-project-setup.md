# Git workflow for a single developer using Claude Code

## The core loop

Every change follows this shape:

1. **Plan** — in Claude, enter plan mode (Shift+Tab twice) or run `/plan`. Agree on the change before any file is touched.
2. **Branch** — `git checkout -b feat/<short-name>` off main.
3. **Small diff** — one logical change at a time. If the diff grows past ~200 LOC, split.
4. **Tests** — every new behavior gets a test in the same branch.
5. **Review** — `/review` or let `code-reviewer` subagent run. Address critical issues.
6. **Ship** — `/ship` runs format → lint → typecheck → test → commit → push.

## Branch naming

Use prefixes so you (and Claude) can tell what a branch is at a glance:

- `feat/` — new feature
- `fix/` — bug fix
- `chore/` — tooling, deps, config
- `docs/` — documentation only
- `refactor/` — behavior-preserving change
- `test/` — test-only additions or fixes
- `exp/` — throwaway experiments (often paired with worktrees)

## Commit messages: Conventional Commits

```
<type>(<optional scope>): <imperative summary ≤72 chars>

<body — WHY, wrap at 72 cols. Omit for trivial changes.>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `style`.

The `/commit` skill generates these from staged diffs (see `templates/commands/commit/SKILL.md`).

## Never commit directly to main

Set a local guard. In `.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
branch="$(git symbolic-ref --short HEAD)"
if [[ "$branch" == "main" || "$branch" == "master" ]]; then
  echo "Refusing to commit directly to $branch. Use a feature branch."
  exit 1
fi
```

Or permissions-wise, deny it in `.claude/settings.json`:

```json
{
  "permissions": {
    "deny": ["Bash(git commit:*)"],
    "ask":  ["Bash(git commit:*)"]
  }
}
```

(Add a rule in CLAUDE.md that Claude always confirms the branch before committing.)

## Worktrees for parallel work

Worktrees let you have multiple branches checked out in separate directories — perfect for spawning a Claude session per experiment.

```bash
# Start an experiment without disturbing your main branch
git worktree add ../myproject-exp-ui exp/new-ui

# In another terminal:
cd ../myproject-exp-ui
claude
```

Each worktree has its own `.claude/` if you copy it, but the project settings are usually shared via the main branch's files. Claude Code's desktop/cloud mode automates this — see Eden Marco Ch 10 on Git worktrees.

Cleanup:

```bash
git worktree remove ../myproject-exp-ui
git branch -D exp/new-ui
```

### When worktrees help
- Trying two approaches to the same problem.
- Long-running refactor + urgent bugfix at the same time.
- Comparing behavior across branches without stashing.

### When they don't
- Changes that depend on each other. Merge conflict hell.
- Very short tasks. The overhead isn't worth it.
- If your dev server / DB / node_modules isn't safe to run concurrently from two dirs.

## Claude Code and git: permission tuning

Recommended starting point (in `templates/core/dot-claude/settings.json`):

- **allow**: `git status`, `git diff:*`, `git log:*`, `git add:*`, `git commit:*`, `git branch:*`
- **ask**: `git push:*`, `git reset:*`, `git rebase:*`, `git checkout:*`
- **deny**: `git push --force`, `git reset --hard` (via block-dangerous-bash hook)

This keeps destructive / public-facing operations gated behind explicit confirmation.

## Pre-commit hooks

Put real guarantees at commit time, not session time:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
      - id: detect-private-key
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.0
    hooks: [{ id: ruff }, { id: ruff-format }]
```

Claude's `format-on-write.sh` hook covers the fast path during the session; pre-commit is the last-line guarantee. Both.

## Ship fast, undo faster

Rewind (`Esc Esc` in Claude Code) and `git reflog` are your safety net. You don't need to be careful with edits — you need to be unafraid to throw them out.

## A realistic day

1. `claude` from the repo root.
2. Describe the task. Claude drafts a plan (via `/plan` or plan mode).
3. Confirm or adjust, then let it edit.
4. `/review` → fix what matters.
5. `/ship` → commits and pushes.
6. Open PR manually or with `gh pr create`. Merge.

Four to six of these cycles is a productive afternoon.
