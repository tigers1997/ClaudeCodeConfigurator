---
paths: ".claude/agents/**"
---
# Multi-agent guardrails

Loads when touching any subagent definition. Parallelism is a multiplier, not a feature — before fanning out work across agents, check the scenario against this list.

## When parallel agents are counterproductive

1. **Tightly coupled features** — the work touches the same files or produces outputs that feed each other. Parallel agents race; run sequential.
2. **Shared state or ordering constraints** — migrations, config files, shared type declarations. One agent must commit before the next reads. Parallel produces merge hell.
3. **Small tasks** — if the whole job would take a single agent under ~15 minutes, the agent startup + merge overhead costs more than you save.
4. **High coordination cost** — if you're writing elaborate specs *just to keep agents from stepping on each other*, the meta-work has already defeated the point. Do it solo.
5. **Exploratory or uncertain work** — parallel multiplies uncertainty. One focused iteration almost always beats five half-blind explorers.

## Pre-flight checklist (use before launching parallel subagents)

- [ ] **Disjoint files.** Each agent's writes land in paths no other agent touches.
- [ ] **Correct starting branch.** All worktrees spawn from the same base commit.
- [ ] **Merged-result test.** Plan how you'll test the integrated output — not just each branch alone.
- [ ] **Cleanup step.** Worktree dirs get removed after merge; dead branches get pruned.

## Rule of thumb

**Solo Claude is the default.** Reach for multi-agent when you have clear, parallelizable work carved into disjoint surfaces — most often: generating N variants of the same component, running independent audits, or processing N isolated files. Everything else, do sequential.
