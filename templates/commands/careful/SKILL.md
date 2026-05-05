---
name: careful
description: Heightened-caution mode for paths — Claude asks for explicit "yes proceed" before each Write/Edit on matching paths.
---

# /careful

Mark paths as "be careful" — every Write/Edit/NotebookEdit on a
matching path triggers a confirmation prompt before the tool fires.

## Usage

`/careful <path-or-glob>`

Examples:

- `/careful auth/**` — I'm working in auth; ask before any change.
- `/careful src/db/migrations/*` — confirm each migration edit.

## How it works

1. `/careful <pattern>` appends the pattern to `.claude/.careful`.
2. PreToolUse hook checks every Write/Edit/NotebookEdit target path
   against the careful list. On match, the hook emits a JSON `ask`
   action to Claude Code, which surfaces a Yes/No prompt to the user.
3. "yes" → tool proceeds. "no" → tool is rejected.

## Output

```
[ CAREFUL ] auth/**

Currently careful:
  - auth/**
```

## When to use

- Touching security-sensitive code.
- Working in a section you understand poorly.
- Pair-programming hand-off — confirm each change.

## Lifecycle

Careful patterns persist for the session, cleared on session start.
