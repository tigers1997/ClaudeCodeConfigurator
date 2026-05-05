<!-- _patterns/no-fix-without-investigation.md
     Embed in any rigor skill via: `include _patterns/no-fix-without-investigation.md` -->

## Iron Law: no fix without investigation

Before proposing or making any code change in response to a bug or
unexpected behavior:

1. **Form a hypothesis** about the root cause — write it down before
   reading more code.
2. **Trace the data flow** through the system to confirm or reject the
   hypothesis. Don't guess; follow the evidence.
3. **Write findings** in this exact shape before any edit:
   - Hypothesis: <what you initially thought>
   - Observations: <what the trace actually showed>
   - Conclusion: <root cause, with evidence>
   - Next-step: <what to do, including "do nothing" if the bug is not what was reported>
4. **Only then** propose a code change.

If three fix attempts fail in a row, halt and re-investigate from
scratch — treat the prior attempts as evidence the hypothesis was wrong,
not as prompts for a fourth attempt.

Skipping this loop is the single biggest hallucination vector in code
generation. The Iron Law is non-negotiable.
