# Slash commands & lifecycle hooks

These are the two automation primitives. Commands are *invoked*; hooks are *triggered*. Know which is which.

## Slash commands (a.k.a. skills)

As of 2026, custom slash commands are merged into the skills system. Both work: `.claude/commands/<name>.md` (legacy) and `.claude/skills/<name>/SKILL.md` (preferred). Same frontmatter, same behavior. Skills win when both exist.

### Anatomy

```markdown
---
name: review
description: Code-review the current branch against main
argument-hint: "[optional focus]"
allowed-tools: Read Grep Glob Bash(git diff:*)
context: fork
agent: code-reviewer
---

# Review

Focus: $ARGUMENTS

...instructions Claude follows...
```

Frontmatter fields worth knowing:
- `description` — when Claude should auto-offer the skill (plus what the user sees with `/`).
- `argument-hint` — autocomplete hint.
- `allowed-tools` — tools usable without per-call approval while the skill runs.
- `context: fork` — run the skill in a forked subagent (own context window). Great for expensive skills that would bloat the main conversation.
- `agent:` — which subagent type when forking (e.g., `Explore`, `Plan`, or one of your own).
- `paths` — glob(s) that auto-activate the skill (model-invoked only).
- `model` / `effort` — override per-skill.

### Argument substitution

- `$ARGUMENTS` — the whole string.
- `$0`, `$1` … — indexed args, shell-quoted (`/foo "a b" c` → `$0="a b"`, `$1="c"`).
- `$name` — named args defined in the `arguments` frontmatter field.
- `${CLAUDE_SKILL_DIR}`, `${CLAUDE_SESSION_ID}` — always available.

### Inline bash with `!`

Inline: `` !`git diff --staged` `` — runs at skill-expansion time, output replaces the placeholder before Claude sees the prompt. Multi-line: fenced block ```` ```! ````.

Great for injecting live repo state into the prompt. The `/review` and `/commit` skills in the template library use this.

### Starter kit

- `/plan` — forces a structured plan before edits.
- `/review` — code review against main.
- `/commit` — Conventional Commits from staged diff.
- `/ship` — full pre-push gauntlet.
- `/sync-docs` — update `CLAUDE.md` / rules from recent work.

Each is in `templates/commands/<name>/SKILL.md`.

## Hooks

Hooks are scripts that run on Claude Code lifecycle events. They're deterministic — they don't depend on the model's judgment. That's the whole point: use hooks for things that must always happen.

### The event surface

Claude Code 2026 fires 27+ events. The ones that matter most day-to-day:

| Event | When it fires | Common use |
|---|---|---|
| `SessionStart` | Session begins or resumes | Inject current git status, prune logs |
| `UserPromptSubmit` | User presses Enter | Log prompts, reject disallowed patterns |
| `PreToolUse` | Before any tool call | Block dangerous bash, scan for secrets |
| `PostToolUse` | After a tool call succeeds | Format files, run fast checks |
| `Stop` | Claude finishes responding | Run tests/lint, summarize |
| `PreCompact` | Before context compression | Snapshot session state to disk |
| `SessionEnd` | Session terminates | Flush logs, send a summary |
| `InstructionsLoaded` | When CLAUDE.md loads | Debug which files are in context |
| `WorktreeCreate` | Before worktree creation | Abort if conditions wrong (only event where nonzero exit code blocks) |

### Handler types

- `command` — shell command. JSON on stdin, decisions via exit code + stdout. The workhorse.
- `http` — POST to a URL. Use when your hook needs to call an external service.
- `prompt` — single-turn LLM evaluation. Expensive; use sparingly.
- `agent` — spawn a subagent. Experimental.

### Exit-code contract

- `0` = success. Stdout may or may not inject context (depends on event).
- `2` = **block**. Stderr is shown to Claude as an error. Stops the action.
- Any other non-zero = non-blocking error. Transcript shows the error; execution continues.

**Exception**: on `WorktreeCreate`, any non-zero aborts.

### Decision JSON (preferred over raw exit codes)

For fine-grained control on `PreToolUse`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: rm -rf pattern"
  }
}
```

Values for `permissionDecision`: `allow`, `deny`, `ask`, `defer`. Precedence across hooks: **deny > defer > ask > allow**.

On `Stop`/`SubagentStop`, two payload surfaces matter for the shipped hooks:

- **Input** (stdin JSON) includes `background_tasks` and `session_crons` arrays on Claude Code 2.1.145+ — they distinguish "session is done" from "session is paused waiting for background work". `stop-run-checks.sh` skips its pass while `background_tasks` is non-empty and runs at the real stop instead.
- **Output** can return `hookSpecificOutput.additionalContext` — feedback injected for Claude's next turn without being labeled a hook error (officially supported on Claude Code 2.1.163+). This is how `stop-run-checks.sh` reports check results.

Hooks have no controlling terminal (`/dev/tty` is unavailable), so a hook that wants to ring a bell or fire a desktop notification returns the escape sequence in the JSON `terminalSequence` field instead (Claude Code 2.1.141+; allowlisted to OSC `0`/`1`/`2`/`9`/`99`/`777` + BEL). `slop-scan.sh` uses an OSC 9 notification this way; set `SLOP_SCAN_PING=0` in the settings `env` block to silence it.

### Starter hooks

From `templates/`:

- **safety** — `block-dangerous-bash.sh`, `scan-secrets.sh` (both PreToolUse).
- **git-workflow** — `format-on-write.sh` (PostToolUse), `stop-run-checks.sh` (Stop).
- **token-efficiency** — `pre-compact-snapshot.sh` (PreCompact).

### Wiring in settings.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-bash.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

The `$CLAUDE_PROJECT_DIR` env var is always set to the project root — use it instead of relative paths. Quote it for Windows compatibility.

### Defaults and caps

- Default timeouts: 600s command, 30s prompt, 60s agent.
- Injected context (additionalContext, systemMessage, stdout) capped at 10,000 chars.
- Multiple hooks per event run in parallel. Identical commands are deduplicated.
- Windows: set `"shell": "powershell"` on command hooks.

### Debugging hooks

- `/hooks` shows what's registered and where it came from (User/Project/Local/Plugin).
- Use the `InstructionsLoaded` hook to log what's in context.
- Write to a file in your hook as well as stdout during development — the transcript only shows the first line of stderr on non-blocking errors.

## When to use which

| Need | Tool |
|---|---|
| A reusable prompt you invoke by name | Slash command / skill |
| A deterministic check that must always happen | Hook |
| A prompt that runs isolated from main context | Skill with `context: fork` |
| A deterministic check that depends on model output | PostToolUse hook + targeted diff parsing |
| A multi-turn specialist | Subagent (see next doc) |
