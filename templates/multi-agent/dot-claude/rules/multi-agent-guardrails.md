---
paths: ".claude/agents/**"
---
# Multi-agent guardrails

Loads when touching any subagent definition. Parallelism is a force multiplier for truly independent work — and a force *divider* for everything else. Before fanning out, check the scenario against the failure modes below.

## Failure modes where parallel is the wrong tool

Grouped by what actually breaks, not by arbitrary ordering:

### Race on shared writes

1. **Overlapping output paths.** Two or more agents target the same file or the same output slot. Even with disjoint *logical* work, literal file collisions corrupt the merge.
2. **Ordering is load-bearing.** Database migrations, schema changes, protocol-version bumps, shared type declarations — anything where the later step needs to see the earlier step's commit to make sense. Parallel races break the sequence.

### Cost > benefit

3. **The task fits in one head.** If a single solo agent would finish in under ~15 minutes, spawn + merge overhead costs more than you save. Solo-Claude is the default for small work.
4. **Specs exist only to separate agents.** If you find yourself writing elaborate boundary specs purely so parallel agents don't collide, the meta-work has already defeated the point. Do it solo.

### Uncertainty multiplier

5. **Unknown-unknowns in the problem shape.** Exploratory or investigative work where the *answer* changes the plan. Parallel agents multiply divergent dead ends.
6. **Active debugging.** Reproducing a bug, tracing a regression, or isolating a flaky test — causality matters, and parallel runs scramble it. One careful session beats three hasty ones.

## Pre-flight — five questions before spawning

Ask all five; a "no" on any of them means stop and rethink.

- [ ] **Disjoint writes?** Each agent's target paths confirmed non-overlapping.
- [ ] **Common base?** All worktrees branch from the same commit hash.
- [ ] **Merged-result test exists?** A check that validates the *integrated* output, not just each branch alone.
- [ ] **Cleanup plan?** Worktrees and merged branches get removed after a successful integration.
- [ ] **Escape hatch?** A clear path to abort and reset if one agent goes sideways — without losing the work of the others.

## Runtime caps to design around (Claude Code ≥ 2.1.217)

- At most 20 subagents run concurrently per session (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`); the 21st spawn fails and the error tells Claude not to retry — size waves accordingly.
- Nesting is capped at 3 levels below the main thread by default (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, since 2.1.219); at the cap the Agent tool is withheld, so a worker that "needs" helpers is a design smell, not a config problem.
- Subagents run in the background by default with a narrower tool set; a fork (`subagent_type: "fork"`) inherits the whole conversation — the opposite of isolation.
- For fan-outs beyond a handful of workers, Claude Code's dynamic Workflows (`ultracode`, or "use a workflow") give you a scripted, resumable pipeline; `/infinite` stays the right tool for N variants of one spec.

## Rule of thumb

**Solo Claude is the default.** Reach for multi-agent when the work is truly parallelizable: N variants of the same spec, N independent audits, N isolated files to process. Everything else, do sequential.

---

*Discipline here draws on a taxonomy presented by Eden Marco in *Agentic Coding with Claude Code* (Packt, 2026), reorganized around failure modes with additional items from the maintainers' own experience.*
