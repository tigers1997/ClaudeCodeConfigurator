# MCP servers cookbook

## Scope cheat sheet
| Scope | File | When to use |
|---|---|---|
| **user** | `~/.claude.json` (via `claude mcp add --scope user`) | Personal servers that work across all your projects (e.g. your docs search). |
| **project** | `.mcp.json` at repo root | Servers the project *requires*. Commit it. |
| **local** | `.claude.json` or `claude mcp add --scope local` | Machine-specific overrides (e.g. different token, different path). Gitignored. |

Precedence when names collide: **local > project > user**.

## Add / remove via CLI
```bash
# Project scope, stdio — note the pinned version
claude mcp add my-server --scope project -- npx -y @modelcontextprotocol/server-filesystem@2026.1.14 /repo

# List what's wired
claude mcp list

# Remove
claude mcp remove my-server
```

## Pinning discipline

Every MCP server reference in this project pins a specific version — no `@latest`, no unpinned names. The reason is supply-chain hygiene: `npx -y <pkg>@latest` installs whatever's current at invocation time without prompting. A compromised or malicious upstream lands in your session the next time you start Claude Code.

When bumping versions:

1. Run a Sonatype lookup (via the MCP tool if you have `SONATYPE_TOKEN` set, or via `https://ossindex.sonatype.org/`) to check the target version for known vulnerabilities, license drift, or end-of-life status.
2. Bump in `templates/mcp/mcp.json`, `templates/mcp/profiles/*.json`, and `configure.py`'s `compute_mcp_json()`.
3. Run `python3 configure.py --check` — CI will also catch any resulting JSON or schema drift.
4. Note the bump in `CHANGELOG.md`.

## Currently pinned versions

| Server | Ref |
| --- | --- |
| `@modelcontextprotocol/server-filesystem` | `2026.1.14` |
| `mcp-server-git` (pypi via `uvx`) | `2026.1.14` |
| `github` (GitHub's official remote MCP) | `https://api.githubcopilot.com/mcp/` (no version — server-side) |
| `@playwright/mcp` | `0.0.70` |
| `@upstash/context7-mcp` | `2.1.8` |

**Deprecated / removed:** `@modelcontextprotocol/server-github` is end-of-life (upstream removed it from the modelcontextprotocol/servers repo). Replaced by GitHub's official remote HTTP MCP, which uses a `type: http` config with `Authorization: Bearer ${GITHUB_TOKEN}` rather than `npx`.

## Tuning knob: `alwaysLoad`

Claude Code 2.1.121 added an `alwaysLoad` boolean to MCP server config. When `true`, every tool from that server bypasses tool-search deferral and is always available in the model's tool list.

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "alwaysLoad": true
    }
  }
}
```

Use sparingly. The default tool-search deferral is what keeps MCP descriptions out of the prompt for tools the model hasn't asked about yet. Setting `alwaysLoad: true` re-burns those tokens unconditionally — only worth it for servers whose tools you call on essentially every turn (e.g., a primary database server in a data-eng project).

For everything else, leave `alwaysLoad` unset and let the model pull tools in as it needs them. If a session needs *guaranteed* loading of one tool group, `claude --mcp-config <profile> --strict-mcp-config` (the `claude-ctx` wrapper this module ships) is usually the cleaner choice.

## Practical picks for a single developer

### Always useful
- **filesystem** — explicit sandboxed file access; pairs well with tight `allowedTools` on subagents.
- **git** — git operations beyond Bash (blame, show, log with structured output).

### Useful when relevant
- **github** — if the project is on GitHub and you want Claude to handle issues/PRs inline.
- **playwright** — any frontend work where you'd otherwise ask Claude to describe what it changed.
- **context7** — live library docs lookup. Saves Claude from guessing API shapes.
- **postgres** / **sqlite** — read-only DB introspection when Claude is writing queries.

### Usually skip
- "Kitchen sink" servers that expose dozens of tools you'll never call. Each tool definition burns context.

## Context hygiene
- **Every MCP server costs tokens** on session start (tool definitions). Only enable what you'll use this week.
- Use per-subagent `mcpServers` frontmatter to scope a heavy server to just the agent that needs it.
- When iterating on MCP choice, run `/context` to see the cost.
- If a server exposes 30 tools and you use 3, write a narrow slash-command wrapper instead.

## Gotchas
- Some servers need env vars. Put tokens in your shell env or `1Password` / `op run`, not in `.mcp.json`.
- Windows paths in `args` need forward slashes or escaped backslashes.
- Restart Claude Code after editing `.mcp.json` for changes to take effect.

## Per-task profiles with `claude-ctx`

A fresh session with 4 MCP servers loaded burns ~49% of a 100k context window before you type anything (system prompt ~2.2k + system tools ~12k + MCP tool descriptions ~37k). For tasks that don't need those servers, scope per-task instead of loading the full default set.

Profiles live at `.mcp.<name>.json` in the project root. Three are shipped by default:

| Profile | Contents | When to use |
|---|---|---|
| `research` | context7 | Reading code you didn't write, investigating APIs, needing accurate library docs |
| `frontend` | playwright | Browser/UI work, regression checks, visual verification |
| `minimal` | (none) | Pure writing or editing sessions — demonstrates the scope savings cleanly |

Run via the shipped wrapper:
```bash
./claude-ctx research          # claude --mcp-config .mcp.research.json --strict-mcp-config
./claude-ctx frontend --resume # any extra args pass through to claude
./claude-ctx                   # no arg -> lists available profiles
```

`--strict-mcp-config` tells Claude Code to ignore the default MCP hierarchy (user/project/local) and only load what's in the specified file. This is the key flag — without it, the per-task file *adds* to the defaults rather than replacing them.

Create your own profile by copying one of the starters and dropping in the servers you actually need for that task class.

## Drift monitor

cc-configure installs a SessionStart hook (`.claude/hooks/sessionstart-drift-check.sh`) that compares `.mcp.json` against `.claude/.cc-manifest.json` on every session startup/resume. If MCP servers were added or removed since the last cc-configure run, the hook emits a one-line system reminder pointing to `/verify-setup`:

```
cc-configure: MCP drift since last cc-configure run — 2 added (shadcn, next-devtools). Run /verify-setup for tradeoffs.
```

Run `/verify-setup` for the deep narrative — per-server purpose, session-start cost, supply-chain vetting nudge (via Sonatype MCP tools), profile-split fit, and a plan-of-attack block.

### Accepting drift

When the new servers are intentional and you want to suppress the alert, re-run cc-configure:

```bash
python3 /path/to/configure.py --persona <your-persona> --yes
```

The retrofit run snapshots the current `.mcp.json` into a fresh baseline; subsequent sessions are silent until the next unannounced change.

### Reverting drift

Edit `.mcp.json` to remove the unwanted entries. The hook will be silent on the next session (baseline matches again).

### Opting out

Two ways to disable drift detection:

1. **Project-level:** delete the `hooks.SessionStart` block from `.claude/settings.json` that points to `sessionstart-drift-check.sh`. The manifest stays on disk as inert state.
2. **Scaffold-time:** run cc-configure with a persona or module set that excludes `mcp` (e.g., `library-author`, or `--modules core,safety,git-workflow`). The hook is module-gated.

### Merge-conflict resolution

`.claude/.cc-manifest.json` is tracked in git so the baseline travels with the repo. If two developers run cc-configure on the same branch and both commit, you'll see a merge conflict on the manifest. Resolution:

- Keep the **newer** `written_at`.
- Take the **union** of `mcp_servers` (lossless: includes whatever both developers had).

A conflict is informative — it signals two parallel scaffold/retrofit events on the same branch. Worth a quick alignment chat with your collaborator about which MCP set you actually want.
