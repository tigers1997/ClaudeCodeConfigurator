<!-- _patterns/independent-verification.md
     Embed in any rigor skill via: `include _patterns/independent-verification.md` -->

## Independent verification

For every finding you intend to report, before output:

1. Re-check the finding from a different angle:
   - Re-read the relevant code path (don't rely on your first scan).
   - Run a test that would fail if the finding is correct.
   - Query a different data source (file vs. git history, AST vs. text).
2. If the finding survives the second-angle check → keep it.
3. If the second-angle check contradicts or doesn't confirm → drop it.

This is the single most reliable filter against confabulation. A finding
that exists on one read but not on a re-read from a different angle is,
empirically, usually a hallucination.
