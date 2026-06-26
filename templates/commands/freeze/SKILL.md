---
name: freeze
description: Pause work — block all Write/Edit/NotebookEdit until /unfreeze. Sets a marker file the microbit-enforcer hook checks.
---

# /freeze

Pause work. While frozen, the microbit-enforcer hook blocks all
Write/Edit/NotebookEdit tool calls. Useful when you want to discuss,
plan, or investigate without code changes happening.

## How it works

1. `/freeze` writes `.claude/.frozen` (an empty marker file).
2. The PreToolUse hook (`microbit-enforcer.sh`, auto-installed by the
   configurator alongside the microbit commands) checks for this file
   before every Write/Edit/NotebookEdit and rejects the tool call when
   present.
3. `/unfreeze` removes the marker.

## When to use

- "Wait, let me think about this before we make changes."
- During a code review where you're discussing, not editing.
- When investigating a bug — you want `/investigate`'s read-only
  behavior to apply session-wide.

## Output

```
[ FROZEN ] All Write/Edit/NotebookEdit calls blocked until /unfreeze.
```

## Notes

- Frozen state is per-project (the marker is in `.claude/`).
- Frozen state is session-scoped: a fresh session (`startup`) or
  `/clear` clears all microbit markers (.frozen / .guarded / .careful),
  but it **survives** `--resume`/`--continue` and compaction — so a long
  session keeps its freeze. Run `/unfreeze` to lift it deliberately.
- Read tools (Read, Grep, Glob, Bash with read-only commands) are
  unaffected.
