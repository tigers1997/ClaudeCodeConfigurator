---
name: unfreeze
description: Resume work after /freeze — removes the .claude/.frozen marker; Write/Edit/NotebookEdit calls allowed again.
---

# /unfreeze

Resume work after `/freeze`. Removes the `.claude/.frozen` marker. The
microbit-enforcer hook stops rejecting Write/Edit/NotebookEdit calls.

## When to use

- After a discussion or planning session, to resume implementation.
- After `/investigate` finishes its findings doc and you're ready to
  apply a fix.

## Output

```
[ UNFROZEN ] Write/Edit/NotebookEdit calls re-enabled.
```
