<!-- _patterns/confidence-gate.md
     Embed in any rigor skill via: `include _patterns/confidence-gate.md` -->

## Confidence gate

Before reporting any finding, suggestion, or claim, rate your internal
confidence on a 1-10 scale based on the evidence you have gathered:

- 1-3: speculation, no evidence
- 4-6: plausible, partial evidence
- 7-8: well-supported, multiple confirming signals
- 9-10: directly verified — the evidence is in the artifact

**Threshold for surfacing:**
- Rigor skills (default): surface only ≥7/10
- Security review: surface only ≥8/10

Findings below the threshold are **silenced**, not "flagged with low
confidence." The noise is the problem; surfacing weak claims trains the
reader to ignore the report. If a finding is below threshold, either
gather more evidence to push it above, or drop it.
