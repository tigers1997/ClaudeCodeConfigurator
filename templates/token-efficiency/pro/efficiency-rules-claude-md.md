These apply on every turn.

### Reading files
- Prefer `grep` / `rg` over `cat` for anything over 50 lines.
- When reading a large file, use `Read` with `offset` + `limit` for the specific slice.
- `ls` only the subdirectory you care about. Never `ls -la` the repo root.

### Running bash
- Use narrowing flags by default: `git diff --stat` before `git diff`, `git log -5` before `git log`, `head -20` / `tail -20` when only a peek is needed.
- Never pipe a full log or test output into the prompt — redirect to a file, tail it if needed.
- Bash output is capped (see `CLAUDE_BASH_MAX_LINES`). If you're truncated, read the full log from `.claude/logs/`.

### Reset rhythm
- At task boundaries, run `/compact` with a focus hint (e.g. `/compact "keep the auth refactor context"`).
- When the task shifts entirely (bug-fix → docs, for example), run `/clear` instead.
- When context usage exceeds 40%, a fresh session with a short pasted summary is cheaper than continuing.

### Planning
- Plan mode is read-only and accumulates no tool output. Use it for the first 2-3 turns of any non-trivial task.

### Subagents
- Delegate verbose tool output (tests, logs, grep results) to subagents. Only the summary returns to the main thread.
- Read-only subagents default to `haiku`. Reserve `sonnet` for code writing and `opus` for security audits or deep refactors.

### Inline bash in skills
- Every `!` substitution in a skill must use a narrowing flag. `!git diff` is a mistake; `!git diff --stat` is correct.
