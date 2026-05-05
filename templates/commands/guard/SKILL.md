---
name: guard
description: Protect specific paths/globs from edits during the session. Adds path patterns to .claude/.guarded; the microbit-enforcer hook rejects Write/Edit on matching paths.
---

# /guard

Protect specific paths from edits during this session. The
microbit-enforcer hook rejects Write/Edit/NotebookEdit on any path
matching a guarded pattern.

## Usage

`/guard <path-or-glob>`

Examples:

- `/guard migrations/**` — don't touch migrations during this refactor.
- `/guard auth.py` — don't change auth code.
- `/guard "src/**/*.proto"` — protect protobuf definitions.

## How it works

1. `/guard <pattern>` appends the pattern to `.claude/.guarded` (one
   per line).
2. PreToolUse hook checks every Write/Edit/NotebookEdit target path
   against the guarded list and rejects on match.

## Output

```
[ GUARDED ] migrations/**

Currently guarded:
  - migrations/**
  - auth.py
```

## Lifecycle

Guards persist for the session. The configurator clears `.guarded` on
session start (SessionStart hook). Removing a single guarded pattern
mid-session isn't supported in v2.1 — re-create the guard list by
clearing it (delete `.claude/.guarded`) and re-running `/guard` for
the patterns you still want.
