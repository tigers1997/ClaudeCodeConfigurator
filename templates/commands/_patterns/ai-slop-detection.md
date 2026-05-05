<!-- _patterns/ai-slop-detection.md
     Embed in any rigor skill via: `include _patterns/ai-slop-detection.md` -->

## AI-slop detection

When reviewing code, comments, or prose under change, scan for these
patterns and flag in a `[ SLOP ]` block (one line per match:
`file:line — pattern: "<excerpt>"`):

**Filler phrases (high-confidence slop):**
- `It is important to note`
- `In essence`
- `Furthermore`
- `Moreover`

**Marketing voice (high-confidence slop):**
- `seamless`
- `elegant`
- `comprehensive`

**Hedging filler (high-confidence slop):**
- `might possibly`
- `perhaps consider`
- `you may want to`

**Em-dash spam:** ≥3 em-dashes (`—`) in a single comment block.

When found in committed code, surface in the review report. When found
in prose under generation, rewrite without the pattern before output.

**Not flagged by default** (high false-positive rate):
- "Note that..." (often legitimate prose)
- "Additionally" (often legitimate prose)
- `robust`, `simply`, `powerful` (legitimate engineering uses)
- Comment density >40% (legitimate for documented APIs)
