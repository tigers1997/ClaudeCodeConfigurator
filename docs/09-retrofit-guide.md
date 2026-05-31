# Retrofitting an existing project

If you're running `cc-configure` against a project that already has Claude Code state — a `CLAUDE.md`, custom skills, hooks, MCP servers — the configurator's defaults are non-destructive. But the *quality* of the result depends on whether your existing `CLAUDE.md` is doing the right job. This doc helps you triage before scaffolding, and explains what the configurator does once you do.

## What `CLAUDE.md` is for, and what it isn't

`CLAUDE.md` loads into context **every single session** in the project. Its tax compounds across thousands of turns. The right shape is short, dense, and load-bearing — the things Claude must remember about *every* file it touches. Anything that's only relevant when working on a specific subsystem belongs in a path-scoped rule (`.claude/rules/<scope>.md` with `paths:` frontmatter) which loads only when Claude reads files matching the glob.

A useful sanity check: **target ~200 lines for `CLAUDE.md`.** Some projects justify more, but past that, you're paying for context you usually don't need.

## What belongs where — a triage checklist

Walk your existing `CLAUDE.md` section by section. For each section, decide which bucket it goes in.

### Stays in `CLAUDE.md` (project-wide, always-relevant)

- **Why the project exists** — one sentence
- **Tech stack** — one line per layer; pointer to `package.json` / `pyproject.toml` for version specifics, not a copy of the version table
- **Commands** — install / dev / test / lint / build (the configurator's intake form captures these)
- **Code style** — naming, indent, max line length, quote style
- **Git workflow** — commit style, branch strategy
- **Project-wide invariants** — security/privacy rules that affect every file ("no secrets in logs," "all data must stay in our region")
- **Working-with-Claude collaboration patterns** — task classification, slot-machine style, commit-as-you-go (the configurator's "Working with Claude" section ships these by default)

### Move to `.claude/rules/<scope>.md` with `paths:` frontmatter

These load only when Claude reads files matching the glob — zero cost on unrelated turns:

- Frontend-specific conventions → `frontend.md` with `paths: "src/frontend/**"`
- Backend / API conventions → `backend.md` with `paths: "src/api/**"`
- Test conventions → `tests.md` with `paths: "**/*.test.*"`
- Migration rules / schema discipline → `migrations.md` with `paths: "migrations/**"`
- AI pipeline rules → `ai-pipeline.md` with `paths: "src/agents/**"`
- Confidence-threshold tables for a review UI → `review-ui.md` with `paths: "src/components/Review/**"`

If a rule applies to one directory tree, it almost certainly belongs in `.claude/rules/`, not in `CLAUDE.md`.

### Move to `docs/<topic>.md`

These are reference material. Claude reads them on demand (via `@docs/path.md` import or natural file-discovery), but they don't load into every session:

- **Architecture diagrams** (ASCII or otherwise) → `docs/architecture.md`
- **Deployment runbook** → `docs/deployment.md` or `DEPLOYING.md`
- **API endpoint table** (30+ rows) → `docs/api.md` (or generated OpenAPI)
- **Database schema DDL** → already in `migrations/` or `schema.sql`; don't duplicate
- **Pipeline flowcharts** → `docs/pipelines.md`
- **Provider/CLI cheat sheets** → `docs/providers.md`

A good question: "if Claude is editing a CSS file, does it need this in context?" If no — it's not session context, it's reference.

### Move to `.github/issues/` or your tracker

- "Known gaps" / "future work" / "TODO" sections — these are issues, not project documentation. Claude doesn't act on them productively when they sit in `CLAUDE.md`; users do, when they triage.

### Delete (it's already in the repo)

- Directory structure trees — Claude can `ls` / `tree`; static trees rot fast
- Inline copies of `docker-compose.yml`, `package.json`, etc. — they're already in the repo
- DDL when the migrations are present
- Inline command help text that's available via `--help`

## The rule of thumb

For each section in your existing `CLAUDE.md`, ask: **"If I were debugging an unrelated CSS bug right now, would this section help?"**

- **Yes** → keep in `CLAUDE.md`
- **Only if I'm working on X** → move to `.claude/rules/X.md` with `paths:`
- **No, but I might want to look it up** → move to `docs/`
- **Already in the repo** → delete

## What `cc-configure` does on a retrofit run

After triage, run `cc-configure --dir <project>`. The non-destructive defaults handle existing state automatically:

| Asset class | Strategy | What you see |
|---|---|---|
| `.claude/settings.json` | Deep-merge | Your `permissions.allow`/`.deny`, custom hooks, custom env vars are preserved; the configurator's additions layer on top. `[ MERGED ]` block summarizes per-file: "preserved existing config; added 12 permission rule(s), 2 hook group(s), 1 env var(s)." |
| `.mcp.json` | Deep-merge | Your custom MCP servers stay; the configurator adds any newly-selected ones. Your server definition wins on key collision. |
| `CLAUDE.md` | Append (default `--claude-md=append`) | Your existing content untouched; configurator appends three value-add sections (`## Working with Claude`, `## Claude Code behavior rules`, `## Token efficiency rules`) at the bottom if they're not already present. Idempotent on re-runs. |
| Skills, agents, rules, hooks | Skip-and-stage (default `--on-collision=skip`) | Your version untouched; configurator's version staged at `.claude-retrofit/incoming/<original-path>` for manual review. |

A `[ COLLISIONS ]` block lists what was staged. `.claude-retrofit/REPORT.md` records the full picture with per-file diff coordinates.

### Resolving staged conflicts

Two paths:

**Manual.** Diff each pair from the report and decide:

```bash
diff -u .claude/skills/review/SKILL.md .claude-retrofit/incoming/.claude/skills/review/SKILL.md
```

For each, decide: keep yours (delete the staged), replace yours with ours (`mv`), merge sections (edit by hand), or install ours alongside (move to `<name>-cc/SKILL.md`).

**Guided (recommended).** Run `/retrofit` in a Claude Code session. The skill walks `.claude-retrofit/REPORT.md` one entry at a time, shows the diff, offers five choices per entry (Keep / Replace / Merge / Rename / Skip), and applies your decision with backups before any destructive op. Available after running `cc-configure` (the skill ships in `commands-core`).

After resolving everything, delete `.claude-retrofit/`. The directory is meant to be ephemeral — its existence means there's pending work.

## The flag reference

When running on an existing project, the relevant flags:

- `--claude-md={append,skip,overwrite}` — default `append`
- `--on-collision={skip,rename,overwrite}` — default `skip`
- `--force` — kill-switch: skip the merge AND the collision strategy; overwrite everything with `*.bak-<ts>`
- `--dry-run` — see exactly what would happen without writing

## Shortcut: a pristine, version-controlled `.claude/`

The default `skip` + `/retrofit` flow exists to protect *local customizations* you haven't committed. If your `.claude/` is **unmodified configurator output that's committed to git** — clean `git status`, no hand-edits — that protection is just ceremony: every staged "conflict" is really a version bump you'd accept anyway. In that case `overwrite` is the cleaner upgrade:

```bash
cc-configure --persona <yours> --yes --on-collision overwrite --no-backup
```

Git is your safety net — `git diff` is the review and `git checkout` is the undo — so there's no `.claude-retrofit/` walk and no `*.bak-<ts>` litter (both are gitignored by the scaffold anyway). The structured assets (`.claude/settings.json`, `.mcp.json`) are still deep-merged, so your settings survive regardless. Stick with the default `skip` flow whenever `.claude/` might hold uncommitted local edits.

## When to skip the configurator

If your existing `CLAUDE.md` is already well-shaped (~200 lines, scope-focused, no inlined reference material) and your `.claude/` already has the skills/agents/hooks you want, you may not need the configurator at all. The value-add sections it appends are useful but not load-bearing — you can copy them by hand from `templates/core/CLAUDE.md`. The configurator earns its keep when:

- You don't have a `CLAUDE.md` yet, OR
- You want the four-pillar collaboration discipline (task classification / slot-machine / commit-as-you-go / spec-driven restart) to land cleanly, OR
- You want a deterministic `.claude/settings.json` permission baseline + safety hooks, OR
- You want `/check-context`, `/verify-setup`, `/session-retro`, etc. as ready-made skills.
