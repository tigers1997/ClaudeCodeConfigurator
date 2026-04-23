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
| `default` | Ask per tool call except allowlisted | Day-to-day |
| `plan` | Read-only. No edits, no bash side-effects | Early exploration |
| `acceptEdits` | Auto-approve Write/Edit; still ask for shell | You trust the plan |
| `auto` | Heuristic auto-approve using a classifier | Fast iteration on well-scoped tasks |
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
    "deny":  ["Write(.env)", "Bash(sudo:*)", "Bash(curl * | sh:*)"]
  }
}
```

Rules of thumb:
- **Allow** the things Claude does dozens of times an hour (read, grep, status, common test commands).
- **Ask** for anything that leaves the local machine or rewrites history (push, reset, rebase, PR operations).
- **Deny** things that should *never* happen from an agent session — writes to `.env`, sudo, pipe-to-shell.

### Patterns that matter

- `Bash(git push:*)` — matches any `git push …`. The colon-star is the prefix match.
- `Write(.env*)` — any Write whose path starts with `.env`.
- `Bash(rm -rf /:*)` — specific dangerous commands.

The starter settings in `templates/core/dot-claude/settings.json` are a balanced baseline.

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
The `code-reviewer` subagent runs against `git diff` or `git diff --merge-base main`. Called explicitly via `/review` or auto-invoked when Claude writes code with "use proactively" description matching.

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
