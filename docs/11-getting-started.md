# Getting started

Two flows, depending on whether you're starting from scratch or retrofitting an existing project.

---

## Two-minute quickstart (newer coders)

```bash
cd ~/projects/my-new-app
cc-configure
# → Persona: pick "solo-newer"
# → Project name: my-new-app
# → Stack preset: e.g. "Python (uv)"
# → Repo URL: (Enter to skip)
# → License: MIT
```

That's the entire intake. The configurator picks a sensible kit (modules, hooks, settings) for a newer-coder persona; documentation fields like "goals" / "non-goals" / "instructions" / "gotchas" default to bracketed `[TODO: ...]` placeholders.

After scaffolding finishes, open `CLAUDE.md` and replace each `[TODO: ...]` block with content specific to your project — they're greppable (`grep TODO: CLAUDE.md`) and idempotent on re-runs of `cc-configure`.

If `solo-newer` feels too constrained later, re-run with `--persona solo-experienced` (more modules, pro tier of token-efficiency) or `--detailed` (full 50-field intake).

---

## Brand-new project (greenfield)

The configurator is good at producing a deterministic baseline, but a baseline is only as useful as the design it serves. For new projects, **brainstorm the design before scaffolding** so the form answers reflect a thought-through plan rather than guesses.

### 1. Install `superpowers` for design-first brainstorming

```bash
claude /plugin install superpowers
```

The `superpowers` plugin (in the official `claude-plugins-official` marketplace) ships a `/brainstorm` command backed by a `brainstorming` skill. The skill enforces a **hard gate**: no implementation, scaffolding, or code-writing until you've presented a design and gotten approval. That's the right discipline for a new project — and the configurator should run *after*, not before.

### 2. Brainstorm the design

```bash
claude
> /brainstorm
```

`superpowers` walks you through:

- Project context (what is this for; who's the user; what's the success criterion)
- Requirements (must-have vs. nice-to-have)
- Visual companions (if UI work)
- Decision points (what trade-offs exist)
- A presented design that captures the above

It iterates one question at a time. Don't let it skip to implementation; the hard-gate is the value.

### 3. Capture the design

Once you and Claude agree on the design, save it to `docs/design.md` (or `DESIGN.md` if you prefer). This becomes the reference point for everything that follows.

```bash
mkdir -p docs
# (paste the agreed design into docs/design.md)
```

### 4. Run `cc-configure` with the design in mind

```bash
cd <your-project>
cc-configure
```

The form asks about your stack, conventions, commands, etc. Most of these are now obvious — the design told you. Pick the appropriate stack preset (Python uv / Node TS / Go / Rust / …); fill in goals/non-goals / common-instructions / known-gotchas with text drawn from the design. The form takes ~3 minutes when you know the answers.

### 5. Install stack-specific plugins

The configurator's default selection includes the `recommend-plugins` module, which generates `docs/recommended-plugins.md` based on your form answers. Open it after the scaffold completes; it lists the official plugins worth installing for your specific stack.

```bash
# Example: a Python + Postgres + FastAPI project gets recommendations like:
claude /plugin install pyright-lsp pydantic-ai cloud-sql-postgresql sentry
```

Re-run `cc-configure` whenever the stack changes — the recommendations refresh.

### 6. Implementation begins

You now have:
- An agreed design in `docs/design.md`
- A scaffolded `.claude/` (CLAUDE.md, settings, hooks, skills, agents)
- Stack-specific plugins installed
- `superpowers` available for ongoing design / TDD / debugging discipline

Use the configurator's `/plan` (or `superpowers`' richer `/brainstorm` + `/write-plan`) to scope the first feature. From there, normal development.

---

## Existing project (retrofit)

You already have a Claude Code setup — maybe a hand-curated `CLAUDE.md`, custom skills, custom hooks. The configurator's defaults are non-destructive; nothing of yours gets clobbered.

### 1. Preview with `--dry-run`

```bash
cd <your-project>
cc-configure --dry-run
```

Shows the full file list with `+` for net-new and `~` for files that would be deep-merged. No writes; safe to run anywhere.

### 2. Run for real

```bash
cc-configure
```

What happens:

- **`.claude/settings.json` and `.mcp.json`** deep-merge with your existing files. Your customizations win on collisions; the configurator's additions layer on top. `[ MERGED ]` block summarizes per-file.
- **`CLAUDE.md`** — the configurator's three value-add sections (`## Working with Claude`, `## Claude Code behavior rules`, `## Token efficiency rules`) are appended to your existing file if they're not already present. Idempotent on re-runs.
- **Skills, agents, rules, hooks** — collisions stage to `.claude-retrofit/incoming/<original-path>`. Your version untouched. `[ COLLISIONS ]` block lists what was staged.
- **`.claude-retrofit/REPORT.md`** records the full picture with diff coordinates.

### 3. Resolve staged conflicts

Two paths:

**Guided (recommended):**

```bash
claude
> /retrofit
```

The `/retrofit` skill (shipped in `commands-core`) walks `.claude-retrofit/REPORT.md` one entry at a time. Per Skipped staging: shows the diff, offers Keep/Replace/Merge/Rename/Skip, applies your decision with `.bak-retrofit-<date>` backups before any destructive op.

**Manual:**

For each pair in the report:

```bash
diff -u .claude/skills/review/SKILL.md \
        .claude-retrofit/incoming/.claude/skills/review/SKILL.md
```

Decide per file: keep yours (delete the staged), replace yours with ours (`mv`), merge sections (edit by hand), or install ours alongside (`mv` to `<name>-cc/SKILL.md`).

### 4. Clean up

After resolving everything, delete `.claude-retrofit/`. The directory is meant to be ephemeral — its existence means there's pending work.

```bash
rm -r .claude-retrofit
```

### 5. Audit + tighten

If the existing `CLAUDE.md` is over ~200 lines, see [`09-retrofit-guide.md`](09-retrofit-guide.md) for the triage discipline (what belongs in `CLAUDE.md` vs. `.claude/rules/<scope>.md` vs. `docs/<topic>.md`). Move the bulky reference content out before sessions; you'll reclaim significant context budget.

Optional: install `claude-md-management` and run its `/revise-claude-md` for an Anthropic-maintained CLAUDE.md auditor.

---

## Daily-use after either flow

Once scaffolded, the configurator's job is done. Day-to-day:

- `/plan` (configurator) or `/brainstorm` (`superpowers`) — scope the next change
- `/review` (configurator) or `feature-dev` plugin's `code-reviewer` agent — review a diff
- `/ship` (configurator) or `commit-commands` plugin's `/commit-push-pr` — push the change
- `/check-context` (configurator) — look at where context is going if sessions feel slow
- `/verify-setup` (configurator) — audit the `.claude/` shape against best practices
- `/session-retro` (configurator) — at end of long sessions, distill learnings back into `CLAUDE.md`

See [`10-plugin-ecosystem.md`](10-plugin-ecosystem.md) for the swap path between configurator skills and their official-plugin equivalents.

## When to re-run `cc-configure`

- **Stack changes** (e.g., switching from JS to TS, adding a database) — re-run to refresh `docs/recommended-plugins.md` and the relevant settings.
- **New configurator version** — the templates may have improvements worth picking up. Run `cc-configure --dry-run` first to see what would change.
- **Form-answer drift** — your project's actual conventions diverge from what's in `CLAUDE.md`. Re-run to re-prompt; the saved `.claude-config.json` makes this near-instant.

The deep-merge + skip-and-stage defaults make re-runs safe; nothing of yours is lost without your explicit say-so.
