---
name: retrofit
description: Walk through `.claude-retrofit/REPORT.md` interactively, resolving each staged conflict from a previous `cc-configure` retrofit run. Reads the report, shows diffs per asset, and applies your decision per file (keep yours, replace, merge, rename, or skip). Use after running cc-configure on an existing project — the configurator stages anything it can't safely auto-merge; this skill walks you through.
allowed-tools: Read Write Edit Glob Grep Bash(diff:*) Bash(cat:*) Bash(ls:*) Bash(mv:*) Bash(cp:*) Bash(rm:*) Bash(mkdir:*) Bash(rmdir:*) Bash(test:*) Bash(stat:*) Bash(find:*)
---

# Retrofit — resolve staged conflicts from a `cc-configure` run

Be careful. You are about to modify files the user already had. Show your work; ask before every destructive action; never silently overwrite.

## Pre-flight

1. Confirm `.claude-retrofit/REPORT.md` exists at the project root. If not, tell the user there's nothing to retrofit and stop. Two reasons it could be missing:
   - They never ran `cc-configure`, or
   - They already resolved everything and deleted the directory (which is the expected end state).
2. Read `.claude-retrofit/REPORT.md` and parse the four section types: **Deep-merged**, **Skipped**, **Renamed**, **Overwritten**.
3. Check `.claude-retrofit/incoming/` — list every file present. These are the staged "ours" candidates that need a decision.
4. Tell the user up front: "I see N staged conflicts to walk through. I'll show each, and you'll choose."

## Per-section handling

### Deep-merged section

Already resolved at scaffold time. **No action.** Mention it as "✅ already merged at scaffold time" so the user knows it's accounted for, then move on.

### Overwritten section

Already resolved at scaffold time (yours got backed up to `*.bak-<ts>`, ours got installed). **No action by default.** Mention it as "✅ already applied; backup at `<path>.bak-<ts>` if you need rollback."

If the user asks to roll one back, restore from the `.bak-<ts>` file with confirmation.

### Renamed section

Both versions installed side-by-side (yours at original path, ours at `<name>-cc`). For each entry, ask: "Keep both, or pick one?"

- **Keep both** (default): no action, move on.
- **Pick yours**: `rm` the `-cc` version after confirmation.
- **Pick ours**: move yours out of the way (e.g., to `<name>.user-version.md`) and rename `-cc` back to the original name. Confirm before any destructive op.

### Skipped section — the main work

For each pair `(yours, ours_staged_at_incoming)`:

1. **Show the diff.** Use `diff -u <yours> <staged>` for one-shot. Cap output at ~120 lines; if larger, note "diff truncated, full file at `<path>`." For binary or large files, show a sizes-and-mtimes summary instead of a literal diff.

2. **Print the choices**:
   - `[K] Keep yours` — delete staged, no change.
   - `[R] Replace yours with ours` — `mv yours yours.bak-retrofit-<date>` then `mv staged yours`.
   - `[M] Merge sections` — propose a merged file by combining your existing sections with the configurator's missing sections, in your own words; user confirms before write.
   - `[N] Install ours alongside (rename to -cc sibling)` — move staged to `<dirname>/<name>-cc.<ext>` (or `<name>-cc/SKILL.md` for skill dirs).
   - `[S] Skip for now` — leave staged untouched, move to the next.

3. **Apply the user's choice.** For Merge mode: do not auto-write. Always show the merged content first, ask for confirmation, then write. Always back up the original to `<path>.bak-retrofit-<YYYYMMDD-HHMM>` before overwriting.

4. **Remove handled stagings.** After K/R/M/N, delete the incoming file from `.claude-retrofit/incoming/<path>` so it doesn't show up next time. After S, leave it.

## Cleanup

After all entries are walked:

1. Summarize what changed: paths replaced, paths merged, paths renamed, paths kept, paths skipped.
2. List remaining stagings in `.claude-retrofit/incoming/` (only the `S`-skipped ones).
3. If the incoming dir is empty (no skips), offer to delete `.claude-retrofit/` entirely. Confirm before `rm -r`.
4. Remind the user to `git status` / `git add` / `git commit` — every change you applied is currently uncommitted.

## What you must not do

- **Never** auto-pick on the user's behalf. Every conflict gets an explicit answer from them.
- **Never** apply a Merge without showing it first.
- **Never** delete `.claude-retrofit/` without confirmation.
- **Never** lose the user's original — always back up to `<path>.bak-retrofit-<date>` before overwriting.
- **Never** trust the staged "incoming" version more than the user's existing one. The configurator's templates are good defaults, not gospel.

## Edge cases

- **Incoming exists but yours is gone**: the user must have moved or deleted theirs between scaffold and now. Treat it as a fresh install: just `mv` the staged file into place, no backup needed.
- **Both yours and incoming are now identical**: no diff to apply. Tell the user, delete the staged file, move on.
- **`.claude-retrofit/REPORT.md` is missing but `incoming/` has files**: the report is the index; without it you can still walk `incoming/` directly and treat each as a Skipped-section entry.
- **User picks Merge but the conflict is structural** (e.g., two skills with the same name doing different things): don't try to glue them. Recommend Rename instead and explain why.

## Output style

- Quiet by default. Don't restate the file paths Claude already knows.
- One question per turn during the walk; let the user breathe.
- At the end, print one tight summary table — one row per file, one column per `before → after`.
