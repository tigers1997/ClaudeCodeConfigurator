#!/usr/bin/env bash
# cc-configure discipline-skills SessionStart bootstrap.
# Injects a terse priming message that names the seven shipped discipline
# skills and instructs the model to invoke them via the Skill tool.
#
# Skip rule: if the upstream `superpowers` plugin is installed, its own
# SessionStart hook already does heavier priming — skip to avoid duplicate
# instructions.
#
# Failure discipline: never break session start. Any unexpected condition
# (missing tool, unreadable file) → exit 0 silently.
set -uo pipefail

# Suppress when the upstream superpowers plugin is also installed (any
# marketplace), since its own SessionStart hook handles priming. Glob covers
# the official marketplace, obra/superpowers-marketplace, and any future
# distribution path under ~/.claude/plugins/cache/<marketplace>/superpowers.
shopt -s nullglob
for d in "${HOME:-/nonexistent}/.claude/plugins/cache"/*/superpowers; do
    if [ -d "$d" ]; then
        shopt -u nullglob
        exit 0
    fi
done
shopt -u nullglob

# Bootstrap text (Claude Code injects this verbatim into the session).
read -r -d '' BOOTSTRAP <<'BOOTSTRAP_EOF' || true
# Discipline skills installed

This project ships seven skills for the major moves in a software task. They are auto-discovered and listed in this session's available-skills set. Invoke them via the Skill tool.

**The seven skills:**
- **brainstorming** — design before code (for creating features, building components, modifying behavior)
- **writing-plans** — break a design into a multi-step implementation plan
- **executing-plans** — run a plan with review checkpoints (single-session)
- **subagent-driven-development** — execute a plan via fresh subagents + two-stage review (preferred when subagents are available)
- **using-git-worktrees** — isolate parallel work in a worktree before implementation
- **verification-before-completion** — run checks and confirm output before claiming success
- **finishing-a-development-branch** — present merge / PR / cleanup options after implementation

**Priority when multiple apply:**
1. Process skills first — `brainstorming`, `writing-plans`, `executing-plans`, `verification-before-completion`
2. Implementation skills second — `subagent-driven-development`, `using-git-worktrees`, `finishing-a-development-branch`

If a skill's trigger description matches the current task, invoke it via the Skill tool before producing the substantive response. These skills operationalize this project's stated principles: plan → small diff → tests → review; verify before shipping; isolate for parallelism.
BOOTSTRAP_EOF

# JSON-escape using bash parameter substitution (single C-level pass per op).
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

BOOTSTRAP_ESCAPED=$(escape_for_json "$BOOTSTRAP")

# Emit the platform-appropriate JSON.
# Claude Code reads hookSpecificOutput.additionalContext.
# Cursor reads additional_context (snake_case).
# Copilot CLI + SDK reads additionalContext (top-level).
if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
    printf '{\n  "additional_context": "%s"\n}\n' "$BOOTSTRAP_ESCAPED"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -z "${COPILOT_CLI:-}" ]; then
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$BOOTSTRAP_ESCAPED"
else
    printf '{\n  "additionalContext": "%s"\n}\n' "$BOOTSTRAP_ESCAPED"
fi

exit 0
