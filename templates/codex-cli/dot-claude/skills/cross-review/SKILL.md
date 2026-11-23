---
name: cross-review
description: Independent cross-vendor review of the current branch. Runs OpenAI's Codex CLI read-only over the diff, then re-checks every finding against the code before showing it. Use before opening a PR, or when a second model family's view is wanted. Sends repository content to the Codex provider.
argument-hint: "[base-ref]"
allowed-tools: Read Grep Glob Bash(git diff:*) Bash(git log:*) Bash(git status)
---

# Cross-review with Codex

A different model family reads this branch's diff cold. It did not write the change, so it does not share the author's blind spots. That independence is the whole value: do not brief Codex on what you think it will find.

**Before running.** Codex reads the repository inside its own read-only sandbox and sends what it reads, plus the diff, to the provider configured in `~/.codex` ({{codex_provider_label}}). Tell the user that in one line and let them decline. The permission prompt for the script is the confirmation; do not work around it.

## Steps

1. Run `.claude/skills/cross-review/scripts/cross-review.sh $ARGUMENTS`. An empty `$ARGUMENTS` compares against the merge-base with `{{default_branch}}`. It prints Codex's report.
   - Exit 2: nothing to review (default branch, empty diff, or no merge-base). Say so and stop.
   - Exit 3: `codex` is not installed. Point to `docs/codex-setup.md`. Do not install it.
   - Any other non-zero exit: show the last lines of the error and stop. Do not retry with different flags.
2. **Check every finding before it reaches the user.** For each one, open the cited `file:line` and read the surrounding code. Keep it only if you can point at the evidence; otherwise mark it *not reproducible* or *needs a human*. Drop findings you would rate below 7 out of 10 rather than reporting them weakly. Codex can be wrong, and so can you, so show both verdicts.
3. Report, most severe first: the finding, Codex's severity, your verdict (confirmed / not reproducible / needs a human) and the `file:line` evidence. Say plainly when Codex found nothing.
4. Offer fixes. Make none unasked.

If `AGENTS.md` has a `## Code Review Rules` section, Codex follows it. A rule that keeps tripping the reviewer, or one it keeps missing, belongs there.
