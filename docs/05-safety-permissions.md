# Safety, permissions & review

Claude Code is an agent with real shell access. Treat it like a very fast but occasionally sloppy collaborator — trust verified by tooling, not by vibes.

## Three layers of defense

1. **Permissions** — what Claude *can* try.
2. **Hooks** — what happens regardless of what Claude tries.
3. **Review** — catching what slipped through.

No single layer is enough. Layer them.

## Layer 1: Permissions

### Modes

Every session runs in a permission mode. The major ones:

| Mode | Behavior | Use when |
|---|---|---|
| `default` (Manual) | Ask per tool call except allowlisted. The starting mode the safety module's discipline profile pins | Day-to-day |
| `plan` | Read-only. No edits, no bash side-effects | Early exploration |
| `acceptEdits` | Auto-approve Write/Edit plus in-scope `mkdir`/`touch`/`rm`/`mv`/`cp`/`sed`; still ask for other shell | You trust the plan |
| `auto` | A classifier reviews actions instead of prompting. Claude Code's own starting mode since 2.1.283/2.1.284; it also routes edits through Bash, so the scaffold's Write/Edit hooks don't fire (see below) | Throwaway work, switched on per session |
| `dontAsk` | Approve everything silently. ⚠️ | Never, unless in a sandbox |
| `bypassPermissions` | Full trust. ⚠️⚠️ | Never on a machine you care about |

Toggle with Shift+Tab. The current mode shows in the status line.

### Allow / ask / deny lists

In `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Read", "Grep", "Bash(git status)", "Bash(npm test:*)"],
    "ask":   ["Bash(git push:*)", "Bash(rm:*)"],
    "deny":  ["Edit(.env)", "Bash(sudo:*)", "Bash(curl * | sh:*)"]
  }
}
```

Rules of thumb:
- **Allow** the things Claude does dozens of times an hour (read, grep, status, common test commands).
- **Ask** for anything that leaves the local machine or rewrites history (push, reset, rebase, PR operations).
- **Deny** things that should *never* happen from an agent session — writes to `.env`, sudo, pipe-to-shell.

### Patterns that matter

- `Bash(git push:*)` — matches any `git push …`. The colon-star is the prefix match.
- `Edit(.env.*)` — any edit whose path starts with `.env.`. `Edit(path)` rules cover the Write and NotebookEdit tools too; `Write(path)`, `NotebookEdit(path)` and `Glob(path)` rules are never consulted and Claude Code 2.1.210+ warns about them at startup — write `Edit()` / `Read()` rules only (a `Read` deny also blocks edits on the same path).
- `Bash(rm -rf /:*)` — specific dangerous commands.

The starter settings in `templates/core/dot-claude/settings.json` are a balanced baseline.

### Starting mode, the classifier, and the discipline profile

Since Claude Code 2.1.283 (the built-in default) and 2.1.284 (interactive terminal and VS Code sessions on every plan and provider), a session with no configured mode starts in **auto mode**: a classifier reviews actions instead of prompting. Paid accounts had it earlier by an account flag. Three things change for a scaffolded project in auto mode:

- **Edits route around the hooks.** While auto mode is active, Claude Code instructs Claude to read with `cat` / `sed -n` and to change files with `sed`, heredocs or short scripts, using Read/Edit/Write only when Bash cannot do the job. `scan-secrets`, `format-on-write`, `slop-scan` and `microbit-enforcer` match only `Write|Edit|NotebookEdit`, so they never see those edits, and `/rewind` has no checkpoint for a `sed -i`.
- **Broad allow rules are dropped on entry**: blanket `Bash(*)`, wildcarded interpreters, package-manager run commands, `Agent` and `Monitor` allow rules. Narrow rules stay. Deny rules apply in every mode, including bypass.
- **Denials are coached around.** The message Claude receives asks it to try a safer method and finish unrelated work before stopping to ask (2.1.268), and the dangerous-`rm` prompt auto-denies after two minutes so unattended sessions keep going (2.1.281).

The safety module's **discipline profile** (`safety.discipline`, on by default for every persona) pins the pre-auto-mode session shape in the committed `.claude/settings.json`:

```json
{
  "permissions": { "defaultMode": "default" },
  "env": {
    "CLAUDE_CODE_FORK_SUBAGENT": "0",
    "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"
  }
}
```

- `defaultMode: "default"` (Manual). Terminal sessions honor every value from a project file except `auto` and `bypassPermissions`, which are ignored from project and local scope since 2.1.257 (`[ SETTINGS WARNINGS ]` flags them). File edits are still auto-approved by the allow list; every other shell command prompts; Claude uses the Edit/Write tools, so the hooks fire. **VS Code never reads a project's starting mode** — set `claudeCode.initialPermissionMode` in VS Code user settings, or `permissions.defaultMode` in `~/.claude/settings.json`.
- `CLAUDE_CODE_FORK_SUBAGENT=0`. While fork mode is on (terminal default since 2.1.232, every host since 2.1.302) Claude cannot wait for a subagent, so `code-reviewer` reports a turn late. Off, the report returns inside the turn.
- `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`. Brings the task-tracking tools back on Opus 4.8+, Sonnet 5, Fable 5 and newer, where 2.1.233 withdrew them.

`discipline_mode` picks the mode: `default` (Manual); `acceptEdits` (also auto-approves in-scope `mkdir` / `touch` / `rm` / `mv` / `cp` / `sed` — a `sed -i` edit then runs silently and bypasses the hooks); or `inspect` (Manual with the whole-tool `Write` / `Edit` allow rules removed, so every edit prompts with its diff — the "core logic, every edit inspected" posture from the CLAUDE.md collaboration patterns; fresh scaffolds only, since a retrofit never removes an existing allow entry). `discipline_strict` adds `disableAutoMode: "disable"`, which removes auto from the Shift+Tab cycle and the "Yes, and switch to auto mode" prompt option for everyone who clones the repo; off by default because a local settings file cannot undo it. A re-run never flips a mode you chose: the retrofit merge keeps an existing `defaultMode` and reports "kept your starting mode".

Shift+Tab still switches modes per session (Manual → Accept edits → Plan → Auto when available). Four companions live outside the committed file, in `~/.claude/settings.json` or `.claude/settings.local.json` (the example file ships the stubs): `useAutoModeDuringPlan: false` (otherwise, with auto mode available, shell commands in plan mode are classifier-reviewed silently; honored from user, local or managed scope only, never from the committed project file), `syncClaudeAiSkills: false` and `syncClaudeAiPlugins: false` (2.1.275+ syncs the account's skills and plugins into terminal sessions, where they crowd the per-turn skill listing and get project skill descriptions dropped), and `idleCompaction: false`.

### Auto-mode rules live in user scope

Auto mode reads its `autoMode` customizations only from `~/.claude/settings.json` or managed settings. It deliberately ignores `.claude/settings.json` and `.claude/settings.local.json` — both live in the repo, so a checked-in file could inject its own allow rules (`code.claude.com/docs/en/auto-mode-config`). Configurator releases before v2.8.0 shipped an `autoMode.hard_deny` block in project settings; that block has been dead since 2.1.207, so the safety module no longer writes it, a retrofit removes the exact shipped block, and `[ SETTINGS WARNINGS ]` flags any other project-scope `autoMode`. To keep the old defaults, add them to `~/.claude/settings.json`:

```json
{
  "autoMode": {
    "hard_deny": ["$defaults", "Running executable files", "Writing to system directories"]
  }
}
```

`"$defaults"` keeps the built-in rules; `soft_deny`, `allow` and `environment` follow the same shape. Two related keys have wider scope: `disableAutoMode: "disable"` is honored from any file (the discipline profile's `strict` option writes it), and `useAutoModeDuringPlan: false` from user, local or managed scope — not from the committed project file.

## Layer 2: Hooks

Permissions are checked against tool-call metadata. Hooks run actual code. Use them for things that need inspection, not just pattern-matching.

### The must-have pair

**`PreToolUse` on Bash — block dangerous commands**
Pattern-matches the command string and exits 2 on matches. See `templates/safety/hooks/block-dangerous-bash.sh`.

Catches: `rm -rf /`, `rm -rf ~`, `rm -rf .`, fork bombs, `mkfs`, `dd of=/dev/…`, `curl | sh`, `chmod -R 777`, `git push --force`, `git reset --hard`.

**`PreToolUse` on Write/Edit — scan for secrets**
Parses the payload, checks the destination path and content against secret patterns. See `templates/safety/hooks/scan-secrets.sh`.

Catches: `.env` writes, API keys (AWS, OpenAI, GitHub, GitLab, Slack), private keys, JWTs.

### Nice-to-have

**`PostToolUse` on Write/Edit — format**
Runs `prettier` / `ruff` / `gofmt` after Claude writes a file. Not a safety check per se, but eliminates the "Claude wrote un-formatted code" category of review comment. See `templates/git-workflow/hooks/format-on-write.sh`.

**`Stop` — run fast checks**
Runs typecheck + lint + impacted tests at the end of each turn. Returns results as `additionalContext` so Claude sees them on the next turn. Never blocks. See `templates/git-workflow/hooks/stop-run-checks.sh`.

**`PreCompact` — snapshot**
Writes a summary of the session to `.claude/logs/` before compression happens. Recoverable record of what was done. See `templates/token-efficiency/hooks/pre-compact-snapshot.sh`.

### Hook writing rules

- **Quote everything.** `"$VAR"`, always. Input contains user strings.
- **Use `$CLAUDE_PROJECT_DIR`** for absolute paths; don't rely on cwd.
- **Don't block on non-critical checks.** Exit 0 and emit additionalContext instead. Exit 2 is a last resort.
- **Timeout defensively.** Set `"timeout": 10` on fast hooks; 60-120 on things that might genuinely take time.
- **Don't print anything you don't want in the transcript.** Stdout may be injected. Write logs to files.

## Layer 3: Review

Automated review is the last line.

### At turn-end
The `code-reviewer` subagent runs against `git diff` or `git diff --merge-base main`. Called explicitly via `/review-branch` or auto-invoked when Claude writes code with "use proactively" description matching.

### At commit-time
The `/commit` skill forces a Conventional Commit message summarizing the change, which forces the model to think about whether the diff actually does what it thinks.

### Before push
The `/ship` skill runs format → lint → typecheck → test → commit → push with confirmations. The gauntlet.

### Periodic
The `security-auditor` subagent runs before any push that touches auth, user input, or external calls. Heavier model (opus), stricter checklist.

## The "never let Claude do" list

For your sanity, bake these into settings + hooks:

- Never write `.env*`.
- Never `sudo`.
- Never pipe downloads to a shell.
- Never `git push --force` without an explicit user confirmation, same turn.
- Never `git reset --hard`.
- Never delete `.git/`, `.claude/`, `.vscode/`, `.idea/`.
- Never commit to `main` or `master` directly.
- Never `chmod -R 777` anything.

All of these are in the starter safety module.

## When a hook fires and you're confused

Run `/hooks` to see what's registered and which file/scope it came from. Enable `InstructionsLoaded` during debugging to log what CLAUDE.md/rules loaded when.

If a hook misbehaves, its transcript entry shows the first line of stderr. Log verbosely to a file in `.claude/logs/` during development.

## Red flags that mean your setup is too loose

- You're approving `Bash(…)` prompts multiple times a minute → tighten allowlist.
- Claude has written secrets or credentials anywhere → turn on secret scan hook immediately.
- A rm or reset destroyed work → turn on block-dangerous-bash hook immediately.
- You keep running `bypassPermissions` "just for this session" → admit you need a wider allow-list and expand it deliberately.

Loosening permissions deliberately is fine. Loosening them from frustration is how you break things.
