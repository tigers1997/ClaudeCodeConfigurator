"""
Shared configuration schema for the Claude Code project configurator.
Consumed by both build_configurator.py (produces the HTML UI) and
configure.py (the headless CLI).

No external dependencies — pure stdlib data.
"""

# ---- module definitions ----
# Each module is a bundle of files + optional settings patches.
# File paths are resolved relative to ./templates/ in the repo root.
MODULES = [
    {
        "id": "core",
        "title": "Core scaffolding",
        "required": True,
        "description": "CLAUDE.md template (populated from the intake form), .claude/settings.json with balanced permissions, .gitignore additions.",
        "paths": [
            "core/CLAUDE.md",
            "core/dot-claude/settings.json",
            "core/dot-claude/settings.local.json.example",
        ],
        "gitignoreSource": "core/.gitignore.append",
    },
    {
        "id": "safety",
        "title": "Safety hooks",
        "description": "PreToolUse hooks: block dangerous bash (rm -rf, sudo, curl | sh, force push, hard reset) and scan Write/Edit for secrets.",
        "paths": [
            "safety/hooks/block-dangerous-bash.sh",
            "safety/hooks/scan-secrets.sh",
        ],
        "settingsPatch": "safety/settings-patch.json",
    },
    {
        "id": "git-workflow",
        "title": "Git workflow hooks",
        "description": "PostToolUse formats files after Claude writes (prettier/ruff/gofmt/rustfmt). Stop hook runs typecheck + lint + tests each turn.",
        "paths": [
            "git-workflow/hooks/format-on-write.sh",
            "git-workflow/hooks/stop-run-checks.sh",
        ],
        "settingsPatch": "git-workflow/settings-patch.json",
    },
    {
        "id": "token-efficiency",
        "title": "Path-scoped rules + compact snapshots",
        "description": "Path-scoped .claude/rules/ starters (frontend/backend/tests). PreCompact hook snapshots session state.",
        "paths": [
            "token-efficiency/dot-claude/rules/_scoping-guide.md",
            "token-efficiency/dot-claude/rules/frontend.md",
            "token-efficiency/dot-claude/rules/backend.md",
            "token-efficiency/dot-claude/rules/tests.md",
            "token-efficiency/hooks/pre-compact-snapshot.sh",
        ],
        "settingsPatch": None,
        "extraSettingsHook": {
            "PreCompact": [
                {
                    "hooks": [
                        {
                            "type": "command",
                            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-compact-snapshot.sh",
                            "timeout": 15,
                        }
                    ]
                }
            ]
        },
    },
    {
        "id": "token-efficiency-pro",
        "title": "Token efficiency PRO",
        "description": "PostToolUse bash-output truncation (cap via CLAUDE_BASH_MAX_LINES) + always-loaded discipline rules (scoped reads, grep-over-cat, inline-bash narrowing, /compact vs /clear vs fresh-session).",
        "paths": [
            "token-efficiency-pro/hooks/truncate-bash-output.sh",
            "token-efficiency-pro/dot-claude/rules/_efficiency-core.md",
        ],
        "settingsPatch": "token-efficiency-pro/settings-patch.json",
    },
    {
        "id": "commands-core",
        "title": "Slash commands (plan/review/commit/ship/sync-docs)",
        "description": "Five workflow skills: /plan, /review vs main, /commit with Conventional Commits, /ship pre-push gauntlet, /sync-docs.",
        "paths": [
            "commands/plan/SKILL.md",
            "commands/review/SKILL.md",
            "commands/commit/SKILL.md",
            "commands/ship/SKILL.md",
            "commands/sync-docs/SKILL.md",
        ],
    },
    {
        "id": "agents",
        "title": "Subagents (code-reviewer/test-runner/doc-writer/security-auditor)",
        "description": "Four specialists with isolated context. Read-heavy ones run on haiku, code-reviewer on sonnet, security-auditor on opus.",
        "paths": [
            "agents/code-reviewer.md",
            "agents/test-runner.md",
            "agents/doc-writer.md",
            "agents/security-auditor.md",
        ],
    },
    {
        "id": "mcp",
        "title": "MCP servers (.mcp.json)",
        "description": "Writes .mcp.json with only the MCP servers you enabled. Plus a cookbook doc.",
        "paths": [
            "mcp/mcp.json",
            "mcp/servers-cookbook.md",
        ],
    },
    {
        "id": "ui",
        "title": "Custom status line + plan output style",
        "description": "Status line script (project dir | branch | model | context %) and a 'plan' output style.",
        "paths": [
            "ui/statusline.sh",
            "ui/output-styles/plan.md",
        ],
        "extraSettings": {
            "statusLine": {
                "type": "command",
                "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/statusline.sh",
            }
        },
    },
]


# ---- intake form schema ----
# Each section is rendered as a collapsible panel in HTML and as a
# section of prompts in the CLI. Every field has a sensible default
# so the impatient user can one-click/Enter through.
FORM_SCHEMA = [
    {
        "id": "identity",
        "title": "Project identity",
        "open": True,
        "fields": [
            {"key": "project_name", "label": "Project name", "type": "text", "default": "my-project"},
            {"key": "one_line_description", "label": "One-line description", "type": "text",
             "default": "A single-developer project.", "wide": True},
            {"key": "repo_url", "label": "Repo URL", "type": "text",
             "default": "git@github.com:user/repo.git", "wide": True},
            {"key": "default_branch", "label": "Default branch", "type": "select",
             "options": ["main", "master", "trunk", "develop"], "default": "main"},
            {"key": "license", "label": "License", "type": "select",
             "options": ["MIT", "Apache-2.0", "GPL-3.0", "BSD-3-Clause", "MPL-2.0",
                         "Proprietary", "Unlicensed", "Other"],
             "default": "MIT"},
        ],
    },
    {
        "id": "goals",
        "title": "Goals & non-goals",
        "fields": [
            {"key": "goals", "label": "Goals (one per line)", "type": "textarea",
             "default": "Ship the core feature reliably.\nKeep the codebase small and readable.\nGreen CI on every push.",
             "help": "Rendered as a markdown bullet list in CLAUDE.md."},
            {"key": "non_goals", "label": "Non-goals (one per line)", "type": "textarea",
             "default": "No multi-tenancy.\nNo heavy framework abstraction.\nNo custom UI framework.",
             "help": "Scope-creep killers."},
        ],
    },
    {
        "id": "stack",
        "title": "Tech stack",
        "fields": [
            {"key": "language", "label": "Language / runtime", "type": "text", "default": "TypeScript 5 on Node 20"},
            {"key": "framework", "label": "Framework", "type": "text", "default": "Next.js 15"},
            {"key": "package_manager", "label": "Package manager", "type": "select",
             "options": ["npm", "pnpm", "yarn", "bun", "pip", "uv", "poetry", "pipenv",
                         "cargo", "go mod", "gradle", "maven", "mix", "other"],
             "default": "pnpm"},
            {"key": "test_runner", "label": "Test runner", "type": "text", "default": "vitest"},
            {"key": "formatter", "label": "Formatter", "type": "text", "default": "prettier"},
            {"key": "typechecker", "label": "Typechecker", "type": "text", "default": "tsc --noEmit"},
            {"key": "build_tool", "label": "Build tool", "type": "text", "default": "next build"},
            {"key": "database", "label": "Database / data store", "type": "text", "default": "Postgres (via Prisma)"},
            {"key": "deployment", "label": "Deployment target", "type": "text", "default": "Vercel"},
        ],
    },
    {
        "id": "commands",
        "title": "Commands cheatsheet",
        "fields": [
            {"key": "cmd_install", "label": "Install", "type": "text", "default": "pnpm install"},
            {"key": "cmd_dev", "label": "Dev", "type": "text", "default": "pnpm dev"},
            {"key": "cmd_test", "label": "Test", "type": "text", "default": "pnpm test"},
            {"key": "cmd_lint", "label": "Lint", "type": "text", "default": "pnpm lint"},
            {"key": "cmd_typecheck", "label": "Typecheck", "type": "text", "default": "pnpm typecheck"},
            {"key": "cmd_build", "label": "Build", "type": "text", "default": "pnpm build"},
        ],
    },
    {
        "id": "style",
        "title": "Style & conventions",
        "fields": [
            {"key": "indent", "label": "Indent", "type": "select",
             "options": ["2 spaces", "4 spaces", "tabs"], "default": "2 spaces"},
            {"key": "max_line", "label": "Max line length", "type": "select",
             "options": ["80", "100", "120", "no limit"], "default": "100"},
            {"key": "quote_style", "label": "Quote style", "type": "select",
             "options": ["single", "double", "backtick-preferred", "follow formatter"], "default": "single"},
            {"key": "naming", "label": "Naming", "type": "text",
             "default": "camelCase for vars/funcs, PascalCase for types/classes, SCREAMING_SNAKE for constants"},
            {"key": "test_philosophy", "label": "Test philosophy", "type": "select",
             "options": ["Tests alongside the code they cover", "TDD \u2014 write tests first",
                         "Smoke tests only", "Integration over unit", "Whatever the module needs"],
             "default": "Tests alongside the code they cover"},
            {"key": "commit_style", "label": "Commit style", "type": "select",
             "options": ["Conventional Commits", "Free-form but imperative",
                         "Ticketed (JIRA-123: ...)", "Other"],
             "default": "Conventional Commits"},
            {"key": "branch_strategy", "label": "Branch strategy", "type": "select",
             "options": ["Trunk-based (short feature branches merged fast)", "GitFlow",
                         "Branch-per-feature (long-lived)", "Solo on main (squash-merge)"],
             "default": "Trunk-based (short feature branches merged fast)"},
        ],
    },
    {
        "id": "design",
        "title": "Design features",
        "fields": [
            {"key": "architecture", "label": "Architecture pattern", "type": "text",
             "default": "Layered: routes \u2192 services \u2192 repositories."},
            {"key": "state_mgmt", "label": "State management (if FE)", "type": "text",
             "default": "React state + URL; Zustand only when shared."},
            {"key": "api_style", "label": "API style", "type": "select",
             "options": ["REST", "GraphQL", "tRPC", "gRPC", "RPC (custom)",
                         "None / CLI only", "Mixed"], "default": "REST"},
            {"key": "auth", "label": "Auth approach", "type": "text",
             "default": "Session cookies via NextAuth."},
            {"key": "observability", "label": "Observability", "type": "text",
             "default": "Structured JSON logs; OpenTelemetry traces; Sentry for errors."},
        ],
    },
    {
        "id": "instructions",
        "title": "Common instructions & gotchas",
        "fields": [
            {"key": "common_instructions", "label": "Common instructions (one per line)",
             "type": "textarea",
             "default": "Prefer editing existing files over creating new ones.\nWhen adding a dependency, call it out in the commit message and explain why.\nIf a function grows beyond 40 lines, split it.\nNever introduce a new pattern without discussing it first.",
             "help": "Rendered as a bullet list. These load every turn \u2014 keep each one punchy."},
            {"key": "known_gotchas", "label": "Known gotchas (one per line)", "type": "textarea",
             "default": "Our test DB uses a non-standard port \u2014 see .env.test.example.\nThe legacy/ directory still uses CommonJS; new work should be ESM only.\nRun migrations before tests on a fresh clone.",
             "help": "The 'Claude will trip on this unless told' list. Prune quarterly."},
            {"key": "pointers",
             "label": "Additional @-imports (one per line, format: @path \u2014 purpose)",
             "type": "textarea",
             "default": "@docs/architecture.md \u2014 system diagram and boundaries\n@docs/workflow.md \u2014 contribution workflow",
             "help": "Appended to the 'Where to look' section. @path expands at load time."},
        ],
    },
    {
        "id": "external",
        "title": "External tools (CLIs & MCPs)",
        "fields": [
            {"key": "clis", "label": "CLIs Claude may use (comma-separated)", "type": "text",
             "default": "git, gh, docker, kubectl, pnpm, psql"},
            {"key": "mcp_filesystem", "label": "MCP: filesystem (sandboxed FS)",
             "type": "checkbox", "default": False,
             "help": "Uncomments filesystem entry in .mcp.json if MCP module is enabled."},
            {"key": "mcp_git", "label": "MCP: git (structured git ops)", "type": "checkbox", "default": False},
            {"key": "mcp_github", "label": "MCP: github (issues, PRs, reviews via API)",
             "type": "checkbox", "default": False},
            {"key": "mcp_playwright", "label": "MCP: playwright (browser automation)",
             "type": "checkbox", "default": False},
            {"key": "mcp_context7",
             "label": "MCP: context7 (live library docs \u2014 stops API hallucinations)",
             "type": "checkbox", "default": True},
        ],
    },
    {
        "id": "efficiency",
        "title": "Token efficiency profile",
        "fields": [
            {"key": "efficiency_preset", "label": "Preset", "type": "select",
             "options": ["Balanced (recommended)", "Aggressive (haiku-first, strict caps)",
                         "Relaxed (correctness over cost)"],
             "default": "Balanced (recommended)",
             "help": "Presets flip the toggles below. You can override individual ones after."},
            {"key": "eff_scoped_reads", "label": "Scoped-reads rule",
             "type": "checkbox", "default": True},
            {"key": "eff_grep_over_cat", "label": "Grep-over-cat rule",
             "type": "checkbox", "default": True},
            {"key": "eff_bash_narrowing", "label": "Inline-bash-narrowing rule",
             "type": "checkbox", "default": True},
            {"key": "eff_reset_rhythm",
             "label": "Reset rhythm: /compact vs /clear vs fresh session",
             "type": "checkbox", "default": True},
            {"key": "eff_plan_mode", "label": "Plan-mode-as-token-saver rule",
             "type": "checkbox", "default": True},
            {"key": "eff_haiku_first",
             "label": "Haiku-first for read-only subagents", "type": "checkbox", "default": True},
            {"key": "eff_effort_minimal",
             "label": "Set effort: minimal on simple skills",
             "type": "checkbox", "default": True},
            {"key": "eff_desc_budget",
             "label": "Add description-budget note (< 500 words total)",
             "type": "checkbox", "default": True},
            {"key": "eff_bash_max_lines", "label": "CLAUDE_BASH_MAX_LINES",
             "type": "select", "options": ["40", "80", "150", "300", "disabled"], "default": "80",
             "help": "Only active if token-efficiency-pro module is selected."},
            {"key": "default_model", "label": "Default model", "type": "select",
             "options": ["sonnet", "haiku", "opus"], "default": "sonnet"},
        ],
    },
]


# ---- path rewriting ----
# Template paths use dot-claude/ (workaround for OneDrive dotfolder blocking);
# they become .claude/ in the target. A few special cases for mcp/ and ui/.
def target_path_for(template_rel: str):
    parts = template_rel.split("/")
    module, *rest = parts
    rest_path = "/".join(rest)
    rest_path = rest_path.replace("dot-claude/", ".claude/")
    if module == "mcp" and rest_path == "mcp.json":
        return ".mcp.json"
    if module == "mcp" and rest_path == "servers-cookbook.md":
        return "docs/mcp-servers.md"
    if module == "core":
        if rest_path == ".gitignore.append":
            return None
        return rest_path
    if rest_path.startswith("hooks/"):
        return f".claude/{rest_path}"
    if rest_path.startswith(".claude/"):
        return rest_path
    if rest_path == "settings-patch.json":
        return None
    if module == "commands":
        return f".claude/skills/{rest_path}"
    if module == "agents":
        return f".claude/agents/{rest_path}"
    if module == "ui":
        if rest_path == "statusline.sh":
            return ".claude/hooks/statusline.sh"
        if rest_path == "output-styles/plan.md":
            return ".claude/output-styles/plan.md"
    return rest_path
