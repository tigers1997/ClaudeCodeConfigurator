#!/usr/bin/env python3
"""
cc-configure — CLI for the Claude Code project configurator.
Runs on headless Debian (or anywhere with Python 3.8+). Pure stdlib.

Usage:
  configure.py                              # 5-question quick mode (default)
  configure.py --detailed                   # full 50-field intake (v1 behavior)
  configure.py --persona solo-newer --yes   # non-interactive, persona-driven
  configure.py --dir /path/to/project       # target a different directory
  configure.py --config .claude-config.json # non-interactive from a saved file
  configure.py --yes \
               --modules core,safety,git-workflow,token-efficiency,commands \
               --yes                        # non-interactive with explicit modules
  configure.py --save-config path.json      # save answers without scaffolding
  configure.py --dry-run                    # show what would be written
"""
import argparse
import base64
import json
import os
import shutil
import stat
import sys
import time
from pathlib import Path

# Load the shared schema from next to this script.
REPO_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO_ROOT))
try:
    from config_schema import (
        CLAUDE_CODE_COMPAT, MODULES, FORM_SCHEMA, STACK_PRESETS, _DEFAULT_STACK,
        target_path_for, PERSONAS,
    )
except ImportError:
    print("ERROR: config_schema.py must be in the same directory as configure.py.", file=sys.stderr)
    sys.exit(2)

TEMPLATE_DIR = REPO_ROOT / "templates"
BASE_SETTINGS_PATH = TEMPLATE_DIR / "core" / "dot-claude" / "settings.json"


# -----------------------------------------------------------------------------
# Colored output (only if stdout is a TTY and NO_COLOR isn't set)
# -----------------------------------------------------------------------------
USE_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def _c(s, code):
    if not USE_COLOR:
        return s
    return f"\033[{code}m{s}\033[0m"


def bold(s): return _c(s, "1")
def dim(s): return _c(s, "2")
def blue(s): return _c(s, "34")
def green(s): return _c(s, "32")
def yellow(s): return _c(s, "33")
def red(s): return _c(s, "31")


# -----------------------------------------------------------------------------
# Defaults from schema
# -----------------------------------------------------------------------------
def default_form_values():
    out = {}
    for section in FORM_SCHEMA:
        for f in section["fields"]:
            out[f["key"]] = f["default"]
    return out


def default_selected():
    # Required modules always, plus a sensible baseline.
    selected = {m["id"] for m in MODULES if m.get("required")}
    selected.update({"safety", "git-workflow", "commands",
                     "token-efficiency",
                     "recommend-plugins"})
    return resolve_dependencies(selected)


def pick_persona_modules(persona: str) -> tuple:
    """Resolve a persona name to (module set, module_flags dict).
    Unknown persona falls back to ('custom', defaults). Required modules
    are always included."""
    p = PERSONAS.get(persona, PERSONAS["custom"])
    required = {m["id"] for m in MODULES if m.get("required")}
    return set(p["modules"]) | required, dict(p["module_flags"])


def infer_persona(selected: set, module_flags: dict) -> str:
    """Score each non-custom persona by how well it matches a translated
    user config; return the closest match or 'custom' if no persona scores
    above 0.5. Used as the default for the v1-upgrade NOTICE prompt so
    users with v1 configs get a sensible inferred suggestion instead of
    a blind 'custom' default.

    Scoring: Jaccard similarity on module sets (weight 0.7) + flag-match
    ratio (weight 0.3). Threshold 0.5 keeps idiosyncratic configs from
    being mislabeled as one of the canonical personas."""
    required = {m["id"] for m in MODULES if m.get("required")}
    sel = set(selected) | required
    best_name, best_score = "custom", 0.0
    for name, p in PERSONAS.items():
        if name == "custom":
            continue
        p_modules = set(p["modules"]) | required
        intersect = len(sel & p_modules)
        union = len(sel | p_modules)
        mod_score = intersect / union if union else 0.0
        flag_total = 0
        flag_matches = 0
        for mid, persona_flags in p.get("module_flags", {}).items():
            user_flags = module_flags.get(mid, {})
            for key, val in persona_flags.items():
                flag_total += 1
                if user_flags.get(key) == val:
                    flag_matches += 1
        flag_score = flag_matches / flag_total if flag_total else 0.0
        score = mod_score * 0.7 + flag_score * 0.3
        if score > best_score:
            best_name, best_score = name, score
    return best_name if best_score >= 0.5 else "custom"


def apply_persona_defaults(persona: str, form_values: dict) -> dict:
    """Apply a persona's form_overrides to form_values, OVERRIDING any existing
    values. Caller is responsible for ordering: apply persona defaults BEFORE
    collecting user-explicit input so that explicit user choices take precedence.

    Design note: spec said setdefault() ("only setting keys not already explicitly
    set"), but default_form_values() pre-fills ALL keys with schema defaults —
    so setdefault() would never override anything in practice.  Direct assignment
    is the correct implementation: persona overrides WIN over schema defaults,
    but user-explicit values set AFTER this call will override persona picks."""
    p = PERSONAS.get(persona, PERSONAS["custom"])
    for k, v in p["form_overrides"].items():
        form_values[k] = v
    return form_values


PLACEHOLDER_TEMPLATES = {
    "goals": ('[TODO: replace with your project goals, one per line.\n'
              ' e.g., "Ship the core feature reliably."\n'
              ' e.g., "Keep CI green on every push."]'),
    "non_goals": ('[TODO: replace with your non-goals, one per line.\n'
                  ' e.g., "No multi-tenancy."\n'
                  ' e.g., "No custom UI framework."]'),
    "common_instructions": ('[TODO: replace with project-specific instructions.\n'
                            ' e.g., "Prefer editing existing files over creating new ones."]'),
    "known_gotchas": ('[TODO: replace with gotchas Claude should know about.\n'
                      ' e.g., "Run migrations before tests on a fresh clone."]'),
    "pointers": ('[TODO: replace with @-imports.\n'
                 ' e.g., "@docs/architecture.md — system diagram and boundaries"]'),
    "repo_url": ('[TODO: replace with your repo URL.\n'
                 ' e.g., "git@github.com:owner/repo.git"\n'
                 ' or "https://github.com/owner/repo.git"]'),
}

# Legacy default that pre-dated the [TODO:] treatment. Recognized as
# "user didn't set this" so saved v2.3.x configs upgrade silently.
_LEGACY_REPO_URL_DEFAULT = "git@github.com:user/repo.git"


def normalize_conditional_placeholders(form_values: dict) -> None:
    """Inject [TODO:] placeholders for fields whose treatment depends on the
    value the user supplied, not on the persona. Currently: `repo_url` — an
    empty string or the legacy literal default both mean "unset", so we stamp
    the [TODO:] template; an explicit value passes through. Idempotent: a
    pre-stamped [TODO:] value is left alone."""
    rv = form_values.get("repo_url", "")
    if isinstance(rv, str) and rv.strip() in ("", _LEGACY_REPO_URL_DEFAULT):
        form_values["repo_url"] = PLACEHOLDER_TEMPLATES["repo_url"]


def inject_placeholders(form_values: dict, persona: str):
    """Replace selected documentation fields with [TODO:] placeholders for the
    persona's `use_placeholders_for` list. Greppable + idempotent: re-running
    against an already-placeholdered field is a no-op (same string)."""
    p = PERSONAS.get(persona, PERSONAS["custom"])
    for key in p.get("use_placeholders_for", []):
        if key in PLACEHOLDER_TEMPLATES:
            form_values[key] = PLACEHOLDER_TEMPLATES[key]


def resolve_dependencies(selected: set) -> set:
    """Expand `selected` to include every module's transitive `dependsOn`.
    Keeps users from ending up with a module selected but one of its declared
    dependencies deselected."""
    by_id = {m["id"]: m for m in MODULES}
    out = set(selected)
    changed = True
    while changed:
        changed = False
        for mid in list(out):
            for dep in by_id.get(mid, {}).get("dependsOn", []):
                if dep not in out:
                    out.add(dep)
                    changed = True
    return out


# -----------------------------------------------------------------------------
# Config persistence
# -----------------------------------------------------------------------------
def load_config(path: Path) -> dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    # Translate any legacy module IDs (lockdown / token-efficiency-pro /
    # commands-core / agents) the same way the --modules CLI path does, so
    # saved v1 configs upgrade in place and deprecations surface uniformly.
    selected, module_flags, deprecations = translate_legacy_modules(
        set(raw.get("selected", default_selected())),
        raw.get("module_flags", {}),
    )
    out = {
        "formValues": {**default_form_values(), **raw.get("formValues", {})},
        "selected": selected,
        "module_flags": module_flags,
        "persona": raw.get("persona", "custom"),
        "schema_version": raw.get("schema_version", 1),
    }
    if deprecations:
        out["_deprecations"] = deprecations
    return out


def save_config(config: dict, path: Path):
    path.write_text(json.dumps({
        "schema_version": 2,
        "persona": config.get("persona", "custom"),
        "module_flags": config.get("module_flags", {}),
        "formValues": config["formValues"],
        "selected": sorted(config["selected"]),
    }, indent=2) + "\n", encoding="utf-8")


# -----------------------------------------------------------------------------
# Placeholder substitution + merge logic (mirrors configurator.html's JS)
# -----------------------------------------------------------------------------
def lines_to_bullets(text: str) -> str:
    if not text or not text.strip():
        return "(none specified)"
    return "\n".join(f"- {l.strip()}" for l in text.splitlines() if l.strip())


def lines_to_pointers(text: str) -> str:
    if not text or not text.strip():
        return ""
    return "\n" + "\n".join(f"- {l.strip()}" for l in text.splitlines() if l.strip())


def build_efficiency_rules(v: dict, tier: str = "basic") -> str:
    rules = []
    if v.get("eff_scoped_reads"):
        rules.append("- **Scoped reads.** Read only the slice you need. Use `Read` with `offset` + `limit` for large files.")
    if v.get("eff_grep_over_cat"):
        rules.append("- **Grep over cat.** Prefer `grep` / `rg` for anything over 50 lines.")
    if v.get("eff_bash_narrowing"):
        rules.append("- **Narrow bash.** `git diff --stat` before `git diff`; `git log -5` before `git log`; `head`/`tail` when peeking.")
    if v.get("eff_reset_rhythm"):
        rules.append("- **Reset rhythm.** Task boundary: `/compact \"focus hint\"`. Task shift: `/clear`. Past 40% context: start fresh with a pasted summary.")
    if v.get("eff_plan_mode"):
        rules.append("- **Plan mode is cheap.** Read-only, no tool-output accumulation. First 2-3 turns of any non-trivial task.")
    if v.get("eff_haiku_first"):
        rules.append("- **Haiku-first for reads.** Read-only subagents default to haiku. Sonnet for writes; opus only for high-stakes review.")
    if v.get("eff_desc_budget"):
        rules.append("- **Description budget.** Keep skill + subagent descriptions under ~500 words total \u2014 they load every turn.")
    cap = v.get("eff_bash_max_lines")
    if cap and cap != "disabled":
        rules.append(f"- **Bash output cap.** Long output truncated past {cap} lines; full log goes to `.claude/logs/`. `tail` it if you need the rest.")

    pro_body = ""
    if tier == "pro":
        pro_body = (TEMPLATE_DIR / "token-efficiency/pro/efficiency-rules-claude-md.md").read_text(encoding="utf-8").rstrip()

    if not rules and not pro_body:
        return ""

    parts = ["## Token efficiency rules"]
    if rules:
        parts.append("\n".join(rules))
    if pro_body:
        parts.append(pro_body)
    return "\n\n".join(parts)


def compute_recommended_plugins(form_values):
    """Stack-specific plugin recommendations from form answers. Returns a
    markdown table body (or a no-match note). Always-recommended plugins
    live in the static template; only stack-specific picks come from here."""
    rows = []

    lang = (form_values.get("language") or "").lower()
    if "python" in lang:
        rows.append(("pyright-lsp", "Python type checking + code intelligence"))
        rows.append(("pydantic-ai", "Up-to-date Pydantic patterns and decision trees"))
        rows.append(("microsoft-docs", "Official Microsoft + Azure docs lookup"))
    if "typescript" in lang or "javascript" in lang or "node" in lang:
        rows.append(("typescript-lsp", "TypeScript / JavaScript code intelligence"))
    # Match Go but avoid false positives like "Mongo" or "Mango".
    if any(tok == "go" for tok in lang.replace(",", " ").split()):
        rows.append(("gopls-lsp", "Go language server + refactoring"))
    if "rust" in lang:
        rows.append(("rust-analyzer-lsp", "Rust code intelligence"))
    if "ruby" in lang:
        rows.append(("ruby-lsp", "Ruby language server + analysis"))
    if "elixir" in lang:
        rows.append(("elixir-ls-lsp", "Elixir language server (ElixirLS)"))
    if "swift" in lang:
        rows.append(("swift-lsp", "Swift language server (SourceKit-LSP)"))
    if any(tok in lang for tok in ("c#", "csharp", "dotnet", ".net")):
        rows.append(("csharp-lsp", "C# language server"))
    if any(tok in lang for tok in ("java ", "kotlin")):
        rows.append(("jdtls-lsp" if "kotlin" not in lang else "kotlin-lsp",
                     "JVM language server"))
    if "php" in lang:
        rows.append(("php-lsp", "PHP language server (Intelephense)"))

    db = (form_values.get("database") or "").lower()
    framework_l = (form_values.get("framework") or "").lower()
    if "postgres" in db:
        if "prisma" in db or "prisma" in framework_l:
            rows.append(("prisma", "Prisma migrations + SQL via MCP"))
        if "neon" in db:
            rows.append(("neon", "Neon Postgres project + branch management"))
        rows.append(("cloud-sql-postgresql", "Cloud SQL Postgres CRUD + schema (or planetscale / supabase if you host elsewhere)"))
    if "mongo" in db:
        rows.append(("mongodb", "MongoDB MCP + skills"))
    if "supabase" in db or "supabase" in framework_l:
        rows.append(("supabase", "Supabase DB + auth + storage + realtime"))
    if any(tok in db for tok in ("cockroach", "crdb")):
        rows.append(("cockroachdb", "CockroachDB cluster management"))
    if "pinecone" in db:
        rows.append(("pinecone", "Pinecone vector DB"))

    if "next" in framework_l:
        rows.append(("frontend-design", "Distinctive frontend interfaces (Tailwind, shadcn)"))
        rows.append(("vercel", "Vercel deployment + build management"))
    if "expo" in framework_l or "react native" in framework_l:
        rows.append(("expo", "Expo build / deploy / upgrade for React Native"))
    if "rails" in framework_l:
        rows.append(("rails-query", "Read-only DB queries against a Rails app"))
    if "laravel" in framework_l:
        rows.append(("laravel-boost", "Laravel development toolkit MCP"))
    if "shopify" in framework_l:
        rows.append(("shopify-ai-toolkit", "18 development skills for the Shopify platform"))

    if form_values.get("mcp_github"):
        rows.append(("github", "Official GitHub MCP (replaces the configurator's wired version)"))
    if form_values.get("mcp_playwright") and not any(r[0] == "playwright" for r in rows):
        rows.append(("playwright", "Browser automation + E2E testing MCP"))
    if form_values.get("mcp_context7"):
        rows.append(("context7", "Live library docs lookup (Upstash Context7)"))

    deployment = (form_values.get("deployment") or "").lower()
    if "aws" in deployment or "lambda" in deployment or "fargate" in deployment:
        rows.append(("aws-serverless", "AWS Serverless: design, build, deploy, debug"))
    if "azure" in deployment:
        rows.append(("azure", "Azure expert mode (Azure MCP server)"))
    if "fly.io" in deployment or "flyctl" in deployment:
        rows.append(("railway", "Adjacent platform (no Fly plugin yet); Railway covers similar ground"))

    obs = (form_values.get("observability") or "").lower()
    if "sentry" in obs:
        rows.append(("sentry", "Sentry error monitoring integration"))
    if "datadog" in obs:
        rows.append(("datadog", "Datadog APM + logs + metrics"))
    if "logfire" in obs:
        rows.append(("logfire", "Logfire observability for Python (FastAPI/Django/Flask)"))
    if "newrelic" in obs.replace(" ", "") or "honeycomb" in obs:
        rows.append(("posthog", "Adjacent observability (PostHog) — not a direct match for what you wrote, but worth a look"))

    # De-dup while preserving order.
    seen = set()
    deduped = []
    for name, why in rows:
        if name in seen:
            continue
        seen.add(name)
        deduped.append((name, why))

    if not deduped:
        return ("_No stack-specific recommendations matched. The always-recommended "
                "set above is a strong universal baseline; install `claude-code-setup` "
                "and ask Claude \"recommend automations for this project\" for "
                "codebase-aware additions._")

    lines = ["| Plugin | Why | Install |", "|---|---|---|"]
    for name, why in deduped:
        lines.append(f"| `{name}` | {why} | `claude /plugin install {name}` |")
    return "\n".join(lines)


def compute_placeholders(form_values: dict, selected: set, module_flags: dict = None) -> dict:
    v = dict(form_values)
    v["goals"] = lines_to_bullets(v.get("goals", ""))
    v["non_goals"] = lines_to_bullets(v.get("non_goals", ""))
    v["common_instructions"] = lines_to_bullets(v.get("common_instructions", ""))
    v["known_gotchas"] = lines_to_bullets(v.get("known_gotchas", ""))
    v["pointers"] = lines_to_pointers(v.get("pointers", ""))
    mcps = []
    if v.get("mcp_filesystem"): mcps.append("filesystem")
    if v.get("mcp_git"):        mcps.append("git")
    if v.get("mcp_github"):     mcps.append("github")
    if v.get("mcp_playwright"): mcps.append("playwright")
    if v.get("mcp_context7"):   mcps.append("context7")
    v["mcps"] = ", ".join(mcps) if ("mcp" in selected and mcps) else "(none)"
    te_tier = (module_flags or {}).get("token-efficiency", {}).get("tier", "basic")
    v["efficiency_rules"] = build_efficiency_rules(form_values, tier=te_tier)
    # Lightweight skills (check-context, sync-docs, session-retro) carry an
    # {{effort_frontmatter}} slot. When the user opts into "effort: minimal
    # on simple skills", stamp it; otherwise leave the slot empty so the
    # next line follows directly.
    v["effort_frontmatter"] = (
        "effort: minimal\n" if form_values.get("eff_effort_minimal") else ""
    )
    # Stack-specific plugin recommendations for the recommend-plugins module.
    # The template ships a static always-recommended block; this fills the
    # "stack-specific" table from the user's form answers.
    v["recommended_plugins"] = compute_recommended_plugins(form_values)
    v["generation_date"] = time.strftime("%Y-%m-%d")
    return v


def substitute_placeholders(text: str, values: dict) -> str:
    import re
    def repl(m):
        k = m.group(1)
        if k in values and values[k] is not None:
            return str(values[k])
        return m.group(0)
    return re.sub(r"\{\{(\w+)\}\}", repl, text)


def deep_merge(a, b):
    if isinstance(a, list) and isinstance(b, list):
        return a + b
    if isinstance(a, dict) and isinstance(b, dict):
        out = dict(a)
        for k, v in b.items():
            out[k] = deep_merge(a[k], v) if k in a else v
        return out
    return b


def compute_merged_settings(form_values: dict, selected: set, module_flags: dict = None) -> dict:
    if module_flags is None:
        module_flags = {}
    base = json.loads(BASE_SETTINGS_PATH.read_text(encoding="utf-8"))
    settings = json.loads(json.dumps(base))
    settings.setdefault("hooks", {})
    settings.setdefault("env", {})

    for m in MODULES:
        if m["id"] not in selected:
            continue
        if m.get("settingsPatch"):
            patch_path = TEMPLATE_DIR / m["settingsPatch"]
            patch = json.loads(patch_path.read_text(encoding="utf-8"))
            patch = {k: v for k, v in patch.items() if not k.startswith("//")}
            settings = deep_merge(settings, patch)
        if m.get("extraSettingsHook"):
            settings["hooks"] = deep_merge(settings.get("hooks", {}), m["extraSettingsHook"])
        if m.get("extraSettings"):
            settings = deep_merge(settings, m["extraSettings"])
        # Apply per-module flag-gated extra patches.
        for flag_name, flag_def in m.get("flags", {}).items():
            selected_value = module_flags.get(m["id"], {}).get(flag_name, flag_def["default"])
            if selected_value:
                extra = flag_def.get("extraSettingsPatch")
                if isinstance(extra, dict):
                    extra = extra.get(selected_value)
                if extra:
                    extra_patch = json.loads((TEMPLATE_DIR / extra).read_text(encoding="utf-8"))
                    extra_patch = {k: v for k, v in extra_patch.items() if not k.startswith("//")}
                    settings = deep_merge(settings, extra_patch)
            # extraSettingsEnv: merge env vars driven by the flag's value.
            # Boolean false ⇒ skip. Otherwise emit each {key: value} pair into
            # settings.env, with the sentinel "$VALUE" replaced by the flag
            # value (used for slop_scan_action where the value IS the env val).
            env_kv = flag_def.get("extraSettingsEnv")
            if env_kv:
                if isinstance(selected_value, bool) and not selected_value:
                    pass
                else:
                    for env_key, env_val in env_kv.items():
                        actual = str(selected_value) if env_val == "$VALUE" else env_val
                        settings.setdefault("env", {})[env_key] = actual

    if form_values.get("default_model"):
        settings["model"] = form_values["default_model"]

    te_tier = module_flags.get("token-efficiency", {}).get("tier", "basic")
    if "token-efficiency" in selected and te_tier == "pro" and form_values.get("eff_bash_max_lines"):
        cap = form_values["eff_bash_max_lines"]
        if cap == "disabled":
            post = settings.get("hooks", {}).get("PostToolUse", [])
            settings["hooks"]["PostToolUse"] = [
                h for h in post
                if "truncate-bash-output" not in " ".join(
                    x.get("command", "") for x in h.get("hooks", []))
            ]
            settings.get("env", {}).pop("CLAUDE_BASH_MAX_LINES", None)
        else:
            settings.setdefault("env", {})["CLAUDE_BASH_MAX_LINES"] = str(cap)

    return settings


HEAVY_INTERPRETERS = {
    "uv", "python", "python3", "node", "poetry", "npm", "npx", "pnpm",
    "bun", "deno", "ruby", "java", "go",
}
HIGH_FREQ_HOOK_EVENTS = ("PreToolUse", "PostToolUse", "PostToolUseFailure")


GOOD_SCHEMA_URL = "https://json.schemastore.org/claude-code-settings.json"


def _parse_version(s: str):
    """Return (major, minor, patch) tuple for version strings like '2.1.119'
    or '2.1.119 (Claude Code)'. Returns None if unparseable."""
    import re
    m = re.match(r"(\d+)\.(\d+)\.(\d+)", s.strip())
    if not m:
        return None
    return tuple(int(x) for x in m.groups())


def check_claude_code_version() -> list:
    """Compare the installed Claude Code version against CLAUDE_CODE_COMPAT.
    Warns if below min_version (several features silently fail) or if claude
    isn't on PATH. Informational note if above tested_up_to. Silent when in range."""
    import subprocess
    try:
        result = subprocess.run(
            ["claude", "--version"], capture_output=True, text=True, timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return [
            f"`claude` CLI not found on PATH — cannot verify compatibility. "
            f"Templates target Claude Code "
            f"{CLAUDE_CODE_COMPAT['min_version']}–{CLAUDE_CODE_COMPAT['tested_up_to']}."
        ]
    if result.returncode != 0:
        return [f"`claude --version` exited {result.returncode} — cannot verify compatibility."]
    found = _parse_version(result.stdout)
    if found is None:
        return [f"Could not parse `claude --version` output: {result.stdout.strip()!r}"]
    min_v = _parse_version(CLAUDE_CODE_COMPAT["min_version"])
    max_v = _parse_version(CLAUDE_CODE_COMPAT["tested_up_to"])
    found_str = ".".join(str(n) for n in found)
    if found < min_v:
        return [
            f"installed Claude Code is {found_str}, below the supported minimum "
            f"{CLAUDE_CODE_COMPAT['min_version']}. Several features will silently "
            f"fail: agent-frontmatter mcpServers http transport (security-auditor's "
            f"Sonatype wiring); DISABLE_UPDATES env (lockdown module); "
            f"permissions.disableBypassPermissionsMode (safety module). "
            f"Upgrade with `npm install -g @anthropic-ai/claude-code@latest` "
            f"(or your install method)."
        ]
    if found > max_v:
        return [
            f"installed Claude Code is {found_str}, newer than the tested range "
            f"(up to {CLAUDE_CODE_COMPAT['tested_up_to']}). Templates likely still "
            f"work but have not been verified against this version. File an issue "
            f"if you see anything odd."
        ]
    return []


def _frontmatter_block(text: str) -> str:
    """Return the YAML frontmatter block between the first two '---' lines, or ''."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[1:i])
    return ""


def run_check() -> int:
    """Static validation of the shipped templates + MODULES registry.
    Exit 0 if everything is fine, 1 with a per-issue summary otherwise.
    Stdlib-only; safe to run in CI."""
    import re
    import subprocess as sp

    module_ids = {m["id"] for m in MODULES}
    issues = []  # list of (severity, source, message)

    def err(source, msg):
        issues.append(("ERR", source, msg))

    # --- 1. MODULES registry integrity ---
    for m in MODULES:
        mid = m["id"]
        # Required keys.
        for req in ("id", "title", "description"):
            if not m.get(req):
                err(f"MODULES[{mid}]", f"missing required key: {req}")
        # Paths exist.
        for rel in m.get("paths", []) or []:
            abs_path = TEMPLATE_DIR / rel
            if not abs_path.exists():
                err(f"MODULES[{mid}]", f"path does not exist: templates/{rel}")
        # settingsPatch file exists.
        patch = m.get("settingsPatch")
        if patch:
            abs_patch = TEMPLATE_DIR / patch
            if not abs_patch.exists():
                err(f"MODULES[{mid}]", f"settingsPatch missing: templates/{patch}")
        # gitignoreSource exists.
        gi = m.get("gitignoreSource")
        if gi:
            abs_gi = TEMPLATE_DIR / gi
            if not abs_gi.exists():
                err(f"MODULES[{mid}]", f"gitignoreSource missing: templates/{gi}")
        # dependsOn references valid module IDs.
        for dep in m.get("dependsOn", []) or []:
            if dep not in module_ids:
                err(f"MODULES[{mid}]", f"dependsOn references unknown module: {dep}")
        # flags schema: required keys + dangling-path detection.
        for flag_name, flag_def in (m.get("flags", {}) or {}).items():
            if "default" not in flag_def:
                err(f"MODULES[{mid}].flags[{flag_name}]", "missing required 'default'")
            if "description" not in flag_def:
                err(f"MODULES[{mid}].flags[{flag_name}]", "missing required 'description'")
            # extraSettingsPatch can be a string or a dict keyed by selected value.
            extra_patch = flag_def.get("extraSettingsPatch")
            patch_candidates = []
            if isinstance(extra_patch, str):
                patch_candidates.append(extra_patch)
            elif isinstance(extra_patch, dict):
                patch_candidates.extend(v for v in extra_patch.values() if v)
            for p in patch_candidates:
                if not (TEMPLATE_DIR / p).exists():
                    err(f"MODULES[{mid}].flags[{flag_name}]",
                        f"extraSettingsPatch missing: templates/{p}")
            # extraPaths is keyed by selected value → list of relative paths.
            for value, path_list in (flag_def.get("extraPaths") or {}).items():
                for p in path_list:
                    if not (TEMPLATE_DIR / p).exists():
                        err(f"MODULES[{mid}].flags[{flag_name}]",
                            f"extraPaths[{value}] missing: templates/{p}")
            # filterPaths values must exist in m["paths"] (allowlist must be a subset).
            for value, path_list in (flag_def.get("filterPaths") or {}).items():
                for p in path_list:
                    if p not in (m.get("paths") or []):
                        err(f"MODULES[{mid}].flags[{flag_name}]",
                            f"filterPaths[{value}] references path not in m[paths]: {p}")

    # --- 2. PERSONAS registry integrity ---
    mod_ids = {m["id"] for m in MODULES}
    for pname, pdef in PERSONAS.items():
        for ref in pdef.get("modules", []):
            if ref not in mod_ids:
                err(f"PERSONAS[{pname}]", f"references unknown module: {ref}")
        for flag_module in pdef.get("module_flags", {}).keys():
            if flag_module not in mod_ids:
                err(f"PERSONAS[{pname}]", f"module_flags references unknown module: {flag_module}")

    # --- 3. Static file checks: walk templates/ once ---
    for f in sorted(TEMPLATE_DIR.rglob("*")):
        if not f.is_file():
            continue
        rel = f.relative_to(TEMPLATE_DIR)
        src = f"templates/{rel}"

        if f.suffix == ".json":
            try:
                # Allow `//`-prefixed comment keys (we use them); json stdlib handles
                # them as regular string keys which is fine.
                json.loads(f.read_text(encoding="utf-8"))
            except json.JSONDecodeError as e:
                err(src, f"invalid JSON: {e}")

        elif f.suffix == ".sh":
            try:
                result = sp.run(["bash", "-n", str(f)], capture_output=True, text=True, timeout=5)
                if result.returncode != 0:
                    err(src, f"bash syntax error: {result.stderr.strip()}")
            except (FileNotFoundError, sp.TimeoutExpired) as e:
                err(src, f"could not run bash -n: {e}")

        elif f.name == "SKILL.md" or (
            # subagents under commands/agents/
            len(rel.parts) >= 3
            and rel.parts[0] == "commands"
            and rel.parts[1] == "agents"
            and f.suffix == ".md"
        ) or (
            # subagents under multi-agent/dot-claude/agents/
            len(rel.parts) >= 3
            and rel.parts[1] == "dot-claude"
            and rel.parts[2] == "agents"
            and f.suffix == ".md"
        ):
            fm = _frontmatter_block(f.read_text(encoding="utf-8"))
            if not fm:
                err(src, "missing YAML frontmatter (--- block at top of file)")
                continue
            if not re.search(r"^name:\s*\S+", fm, flags=re.MULTILINE):
                err(src, "frontmatter missing required `name:` field")
            if not re.search(r"^description:\s*\S+", fm, flags=re.MULTILINE):
                err(src, "frontmatter missing required `description:` field")

    # --- 4. Cross-cutting pattern integration (rigor skills) ---
    # Each rigor skill must embed its named pattern blocks via `include
    # _patterns/<name>.md` references. Catches drift where a future edit
    # accidentally drops the discipline rule from a skill.
    pattern_requirements = {
        "commands/investigate/SKILL.md": [
            "_patterns/no-fix-without-investigation.md",
            "_patterns/confidence-gate.md",
            "_patterns/independent-verification.md",
        ],
        "commands/plan-eng-review/SKILL.md": [
            "_patterns/confidence-gate.md",
            "_patterns/independent-verification.md",
        ],
        "commands/review/SKILL.md": [
            "_patterns/confidence-gate.md",
            "_patterns/independent-verification.md",
            "_patterns/ai-slop-detection.md",
        ],
        "commands/agents/security-auditor.md": [
            "_patterns/confidence-gate.md",
            "_patterns/independent-verification.md",
        ],
    }
    for skill_rel, required in pattern_requirements.items():
        abs_path = TEMPLATE_DIR / skill_rel
        if not abs_path.exists():
            continue  # skill not yet present (early PR — soft-fail)
        text = abs_path.read_text(encoding="utf-8")
        for pat in required:
            if f"include {pat}" not in text:
                err(f"templates/{skill_rel}", f"missing required pattern include: {pat}")

    # --- Report ---
    if not issues:
        print(green("✓ all checks passed"))
        print(dim(f"  modules: {len(MODULES)}"))
        print(dim(f"  scanned: {sum(1 for _ in TEMPLATE_DIR.rglob('*') if _.is_file())} files under templates/"))
        print(dim(f"  Claude Code compat: {CLAUDE_CODE_COMPAT['min_version']}"
                  f"–{CLAUDE_CODE_COMPAT['tested_up_to']}"))
        return 0

    print(red(f"✗ {len(issues)} issue(s) found"))
    for sev, src, msg in issues:
        print(f"  {red(sev)} {src}: {msg}")
    return 1


def check_schema_url(settings: dict) -> list:
    """Guard against the regression class that motivated the first $schema fix:
    Claude Code silently drops the entire settings file if $schema is present
    but not the expected value. Returns a warning only on drift."""
    warnings = []
    schema = settings.get("$schema")
    if schema is None:
        warnings.append(
            "settings.json has no $schema key — the file is valid but editors "
            f"won't offer autocomplete. Expected: {GOOD_SCHEMA_URL}"
        )
    elif schema != GOOD_SCHEMA_URL:
        warnings.append(
            f"settings.json $schema = {schema!r} but Claude Code's validator "
            f"accepts only {GOOD_SCHEMA_URL!r}. Files with this mismatch are "
            f"rejected silently and all settings are ignored."
        )
    return warnings


def check_github_remote(target_dir) -> list:
    """Return warnings if the github-actions module was selected but the target
    dir isn't a GitHub-tracked git repo. Non-blocking — the workflow file will
    still be written; it just won't do anything until the remote is set up."""
    import subprocess
    warnings = []
    try:
        result = subprocess.run(
            ["git", "-C", str(target_dir), "remote", "-v"],
            capture_output=True, text=True, timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        warnings.append("`git` not found or unresponsive — cannot verify GitHub remote")
        return warnings
    if result.returncode != 0:
        warnings.append(
            "target dir is not a git repo — the Action will not run until "
            "you `git init` and push to a GitHub remote"
        )
    elif "github" not in result.stdout.lower():
        existing = result.stdout.strip() or "(no remotes configured)"
        warnings.append(
            f"no GitHub remote detected. `git remote -v` shows: {existing}"
        )
    return warnings


def check_mcp_env_vars(form_values: dict, selected: set) -> list:
    """Return warnings for declared MCP/agent surfaces whose required env vars
    aren't set in the running shell. Catches the common dogfood failure mode
    where a user enables an MCP server (or selects an agent that scopes one)
    and discovers the server silently never connects because they forgot to
    export the auth token.

    Mappings are static because each MCP we ship has a single, known auth env
    var. If we add MCPs whose auth requirements are dynamic, replace this with
    a regex scan over the rendered .mcp.json + selected agent frontmatter."""
    import os
    warnings = []
    # MCP servers declared in compute_mcp_json() that need shell-env auth.
    if form_values.get("mcp_github") and not os.environ.get("GITHUB_TOKEN"):
        warnings.append(
            "MCP server 'github' is enabled but GITHUB_TOKEN is not set in "
            "your shell — the server will fail to connect at session start. "
            "Generate a PAT (https://github.com/settings/tokens) and "
            "`export GITHUB_TOKEN=...`, or remove the github MCP."
        )
    # Agent-scoped MCPs (only activate when the agent is invoked).
    if "commands" in selected and not os.environ.get("SONATYPE_TOKEN"):
        warnings.append(
            "agent 'security-auditor' scopes the Sonatype MCP for vuln "
            "lookups; it needs SONATYPE_TOKEN. The agent will still run but "
            "the MCP won't connect. Generate a token "
            "(https://guide.sonatype.com/settings/tokens) and "
            "`export SONATYPE_TOKEN=...` if you want CVE/license data."
        )
    return warnings


def check_deprecations(deprecations: list) -> list:
    """Echo legacy-flag/module-name translations as user-facing warnings.
    Mirrors the check_X() pattern: returns a list of strings to render in
    a [ DEPRECATED ] block. Empty when nothing legacy was used."""
    return list(deprecations or [])


def check_placeholders(form_values: dict) -> list:
    """Returns list of (field, line_excerpt) for any [TODO:] placeholder
    present in the rendered values. Caller renders these as a [ PLACEHOLDERS ]
    block."""
    out = []
    for k, v in form_values.items():
        if isinstance(v, str) and v.startswith("[TODO:"):
            first_line = v.splitlines()[0][:80]
            out.append((k, first_line))
    return out


def render_applied_block(persona: str, selected: set, module_flags: dict,
                         overrides: list = None) -> list:
    """Returns a list of strings to render under [ APPLIED ].

    Lists the persona name + the final module set with active flag values
    inline (e.g. `commands (subset=full)`). Modules ordered per the canonical
    MODULES list for stable output. When `overrides` is non-empty, appends a
    `Persona overrides:` block listing flag values the persona changed from
    user-set values — surfaces silent overrides on v1 upgrades and
    `--persona` re-runs against an existing config."""
    out = ["Persona  {}".format(persona or "custom")]
    canonical = [m["id"] for m in MODULES if m["id"] in selected]
    flag_strs = []
    for mid in canonical:
        fkv = (module_flags or {}).get(mid, {})
        if fkv:
            kv = ", ".join("{}={}".format(k, v) for k, v in sorted(fkv.items()))
            flag_strs.append("{} ({})".format(mid, kv))
        else:
            flag_strs.append(mid)
    out.append("Modules  " + ", ".join(flag_strs))
    if overrides:
        out.append("Persona overrides:")
        for mid, key, before, after in overrides:
            out.append("  {}.{}: {} → {}".format(mid, key, before, after))
    return out


def detect_persona_overrides(pre_flags: dict, persona: str) -> list:
    """Returns (module, key, before, after) tuples where the persona's flag
    pick conflicts with a flag the user had explicitly set in their saved
    config. Skips additions (persona introduces a new flag the user never
    had) since those aren't overrides — they're augmentations."""
    p = PERSONAS.get(persona, {})
    overrides = []
    for mid, persona_flags in p.get("module_flags", {}).items():
        pre = pre_flags.get(mid, {})
        for key, after in persona_flags.items():
            if key in pre and pre[key] != after:
                overrides.append((mid, key, pre[key], after))
    return overrides


def check_design_docs(target_dir) -> list:
    """Return paths to design/spec/plan docs found at target_dir, relative to
    target_dir. Used to detect "designed but unscaffolded" projects (typically
    the output of a prior superpowers brainstorming session) so the configurator
    can nudge folding the design into CLAUDE.md instead of shipping its generic
    template untouched.

    Heuristic: anything under docs/ whose basename matches design.md, spec.md,
    or plan.md, plus everything under docs/superpowers/. Returns a sorted list
    of relative path strings."""
    docs_dir = target_dir / "docs"
    if not docs_dir.is_dir():
        return []
    found = []
    for name in ("design.md", "spec.md", "plan.md"):
        p = docs_dir / name
        if p.is_file():
            found.append(f"docs/{name}")
    sp_dir = docs_dir / "superpowers"
    if sp_dir.is_dir():
        for p in sorted(sp_dir.rglob("*.md")):
            found.append(str(p.relative_to(target_dir)))
    return found


def _merge_unique_list(existing_list, new_list):
    """Concatenate existing + new, preserving order, dropping duplicates by
    equality. Existing items keep their relative order; new items append in
    order, skipping any already present in existing."""
    out = list(existing_list)
    for item in new_list:
        if item not in out:
            out.append(item)
    return out


def deep_merge_settings(existing: dict, new: dict):
    """Merge a user's existing .claude/settings.json with the configurator's
    new version. Returns (merged_dict, summary_str).

    Strategy:
      - $schema: ours always wins (canonical schemastore URL).
      - permissions.allow / .ask / .deny / .additionalDirectories: union,
        existing entries first, new entries appended without duplicates.
      - permissions.disableBypassPermissionsMode: ours wins (security default
        the user opted into by selecting safety).
      - hooks: concatenate per-event groups (existing first, then ours). No
        dedupe — if the user has a hook group with the same matcher, both
        run; user can manually remove duplicates if undesired.
      - env: dict merge with existing keys winning on collision (preserves
        user's deliberate overrides).
      - statusLine, model: preserve existing if set; otherwise use new.
      - Unknown top-level keys: pass through verbatim from existing.
    """
    out = dict(existing)
    counts = {"perms_added": 0, "hook_groups_added": 0, "env_added": 0}

    if "$schema" in new:
        out["$schema"] = new["$schema"]

    if "permissions" in new:
        out_perms = dict(out.get("permissions", {}))
        new_perms = new["permissions"]
        for key in ("allow", "ask", "deny", "additionalDirectories"):
            if key in new_perms:
                existing_list = out_perms.get(key, [])
                merged = _merge_unique_list(existing_list, new_perms[key])
                counts["perms_added"] += len(merged) - len(existing_list)
                out_perms[key] = merged
        if "disableBypassPermissionsMode" in new_perms:
            out_perms["disableBypassPermissionsMode"] = new_perms["disableBypassPermissionsMode"]
        out["permissions"] = out_perms

    if "hooks" in new:
        out_hooks = dict(out.get("hooks", {}))
        for event, new_groups in new["hooks"].items():
            existing_groups = out_hooks.get(event, [])
            out_hooks[event] = list(existing_groups) + list(new_groups)
            counts["hook_groups_added"] += len(new_groups)
        out["hooks"] = out_hooks

    if "env" in new:
        out_env = dict(new["env"])
        for k, v in out.get("env", {}).items():
            out_env[k] = v  # existing overlays
        existing_env_keys = set(out.get("env", {}).keys())
        counts["env_added"] = sum(1 for k in new["env"] if k not in existing_env_keys)
        out["env"] = out_env

    for k in ("statusLine", "model"):
        if k in new and k not in existing:
            out[k] = new[k]

    handled = {"$schema", "permissions", "hooks", "env", "statusLine", "model"}
    for k, v in new.items():
        if k not in out and k not in handled:
            out[k] = v

    msg = (f"preserved existing config; added {counts['perms_added']} permission rule(s), "
           f"{counts['hook_groups_added']} hook group(s), {counts['env_added']} env var(s)")
    return out, msg


def deep_merge_mcp(existing: dict, new: dict):
    """Merge a user's existing .mcp.json with the configurator's. Returns
    (merged_dict, summary_str). User's server definitions win on key collision
    — they explicitly customized them; don't clobber."""
    out = dict(existing)
    new_servers = new.get("mcpServers", {})
    out_servers = dict(out.get("mcpServers", {}))
    preserved = len(out_servers)
    added = 0
    for name, config in new_servers.items():
        if name not in out_servers:
            out_servers[name] = config
            added += 1
    out["mcpServers"] = out_servers
    msg = f"preserved {preserved} existing server(s), added {added} new"
    return out, msg


def apply_structured_merges(files, target_dir):
    """Walk `files` and deep-merge any structured assets (.claude/settings.json
    and .mcp.json) that already exist at the target. Mutates the matching
    file dict's `content` and adds a `was_merged` flag. Returns a list of
    (target_relative_path, summary_str) tuples for the [ MERGED ] report.

    Files with unparseable existing JSON are left alone — they'll fall through
    to the Tier 1 retrofit-collision check and abort unless --force is set."""
    messages = []
    for f in files:
        target = f["target"]
        if target not in (".claude/settings.json", ".mcp.json"):
            continue
        dest = target_dir / target
        if not dest.exists():
            continue
        try:
            existing_data = json.loads(dest.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue  # leave Tier 1 to handle the abort
        new_data = json.loads(f["content"])
        if target == ".claude/settings.json":
            merged_data, msg = deep_merge_settings(existing_data, new_data)
        else:
            merged_data, msg = deep_merge_mcp(existing_data, new_data)
        f["content"] = json.dumps(merged_data, indent=2) + "\n"
        f["was_merged"] = True
        messages.append((target, msg))
    return messages


VALUEADD_HEADINGS = [
    "## Working with Claude (collaboration patterns)",
    "## Claude Code behavior rules",
    "## Token efficiency rules",
]


def _extract_section(text, heading):
    """Find a markdown section starting at `heading` (matched as a whole-line
    prefix) and return the heading line + body up to the next ## or ### heading
    at the same level or higher, or EOF. Returns None if heading not found."""
    import re
    # Match the heading line, then capture everything until another top-level
    # markdown heading (## not preceded by # — i.e., level 2 or higher) or EOF.
    pattern = re.escape(heading) + r"\n(.*?)(?=\n##(?!#)|\Z)"
    m = re.search(pattern, text, re.DOTALL)
    if not m:
        return None
    return heading + "\n" + m.group(1).rstrip()


def _append_missing_valueadd_sections(existing_text, generated_text):
    """Find configurator value-add sections in `generated_text` that are
    missing from `existing_text`, and return the existing text with those
    sections appended at the bottom. Returns:
      - {"merged": "...", "count": N, "appended": [heading, ...]} on append
      - None if all sections already present in existing
    Detection is by exact heading match — same-text-different-section is
    treated as "user has it, don't double up.\""""
    appended_headings = []
    appended_sections = []
    for heading in VALUEADD_HEADINGS:
        if heading in existing_text:
            continue
        section = _extract_section(generated_text, heading)
        if section is None:
            continue  # not in generated either (e.g., efficiency_rules empty)
        appended_headings.append(heading)
        appended_sections.append(section)
    if not appended_sections:
        return None
    sep = "\n\n" if existing_text.endswith("\n") else "\n\n\n"
    merged = existing_text.rstrip() + sep + "\n\n".join(appended_sections) + "\n"
    return {"merged": merged, "count": len(appended_sections),
            "appended": appended_headings}


def apply_claudemd_strategy(files, target_dir, strategy):
    """Handle CLAUDE.md collision according to --claude-md strategy.
    Returns (merge_msg, collision_entry, files_out):
      - merge_msg: ("CLAUDE.md", <human msg>) for [ MERGED ] block, or None
      - collision_entry: dict for collision_report, or None
      - files_out: input files with CLAUDE.md mutated/dropped as needed

    Strategies:
      - append (default): merge-append valueadd sections; if all present,
        leave existing untouched and drop CLAUDE.md from the write list
        (idempotent on re-runs).
      - skip: stage our CLAUDE.md to .claude-retrofit/incoming/CLAUDE.md;
        existing untouched. Same shape as --on-collision=skip.
      - overwrite: pass through to normal apply_files write; existing gets
        backed up to .bak-<ts>.
    """
    import stat as _stat
    out = []
    merge_msg = None
    collision_entry = None
    for f in files:
        if f["target"] != "CLAUDE.md":
            out.append(f)
            continue
        dest = target_dir / "CLAUDE.md"
        if not dest.exists():
            # No collision — pass through to normal write.
            out.append(f)
            continue
        if strategy == "append":
            existing_text = dest.read_text(encoding="utf-8")
            result = _append_missing_valueadd_sections(existing_text, f["content"])
            if result is None:
                # All sections present — drop CLAUDE.md from write list.
                merge_msg = ("CLAUDE.md", "all value-add sections already present; left untouched")
                # Don't add f to out.
            else:
                f["content"] = result["merged"]
                f["was_merged"] = True
                merge_msg = ("CLAUDE.md",
                             f"appended {result['count']} value-add section(s) "
                             f"({', '.join(h.lstrip('# ').rstrip() for h in result['appended'])})")
                out.append(f)
        elif strategy == "skip":
            staged = target_dir / ".claude-retrofit" / "incoming" / "CLAUDE.md"
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_text(f["content"], encoding="utf-8")
            collision_entry = {
                "target": "CLAUDE.md",
                "action": "skip",
                "incoming": str(staged.relative_to(target_dir)),
            }
            # Drop f from out.
        else:  # overwrite
            collision_entry = {
                "target": "CLAUDE.md",
                "action": "overwrite",
                "backup": "CLAUDE.md.bak-<ts>",
            }
            out.append(f)
    return merge_msg, collision_entry, out


def collision_renamed_target(target_path):
    """Append a `-cc` suffix to the unique-name component of a target path
    so the configurator's version installs alongside the user's instead of
    overwriting it. Examples:
      .claude/skills/review/SKILL.md     -> .claude/skills/review-cc/SKILL.md
      .claude/agents/code-reviewer.md    -> .claude/agents/code-reviewer-cc.md
      .claude/rules/_scoping-guide.md    -> .claude/rules/_scoping-guide-cc.md
      .claude/hooks/scan-secrets.sh      -> .claude/hooks/scan-secrets-cc.sh
    """
    parts = target_path.split("/")
    if len(parts) >= 4 and parts[-3] == "skills" and parts[-1] == "SKILL.md":
        # Skill dirs: rename the directory, keep SKILL.md as-is.
        parts[-2] = parts[-2] + "-cc"
        return "/".join(parts)
    last = parts[-1]
    if "." in last:
        stem, ext = last.rsplit(".", 1)
        parts[-1] = f"{stem}-cc.{ext}"
    else:
        parts[-1] = last + "-cc"
    return "/".join(parts)


def apply_file_collision_strategy(files, target_dir, strategy):
    """Walk non-structured collisions and apply the chosen strategy. Returns
    (new_files_list, report_entries). Files already merged via
    apply_structured_merges (was_merged flag) and files that don't collide
    pass through untouched.

    Strategies:
      - skip: pop from files list; stage f['content'] to
        .claude-retrofit/incoming/<original-path>; record in report.
      - rename: change f['target'] to a -cc-suffixed sibling; record.
      - overwrite: leave in files list; record (apply_files writes with .bak).
    """
    import stat as _stat
    report = []
    out = []
    incoming_dir = target_dir / ".claude-retrofit" / "incoming"
    for f in files:
        target = f["target"]
        dest = target_dir / target
        if not dest.exists() or f.get("was_merged"):
            out.append(f)
            continue
        if target == "CLAUDE.md":
            # CLAUDE.md is handled by apply_claudemd_strategy, not this one.
            out.append(f)
            continue
        # Non-structured collision — apply strategy.
        if strategy == "skip":
            staged = incoming_dir / target
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_text(f["content"], encoding="utf-8")
            if f.get("executable"):
                staged.chmod(staged.stat().st_mode | _stat.S_IXUSR | _stat.S_IXGRP | _stat.S_IXOTH)
            try:
                identical = dest.read_text(encoding="utf-8") == f["content"]
            except (OSError, UnicodeDecodeError):
                identical = False
            report.append({
                "target": target,
                "action": "skip",
                "incoming": str(staged.relative_to(target_dir)),
                "identical": identical,
            })
            # Drop from files list (don't write to original location).
        elif strategy == "rename":
            renamed = collision_renamed_target(target)
            f["target"] = renamed
            report.append({
                "target": target,
                "action": "rename",
                "renamed_to": renamed,
            })
            out.append(f)
        else:  # overwrite
            report.append({
                "target": target,
                "action": "overwrite",
                "backup": f"{target}.bak-<ts>",
            })
            out.append(f)
    return out, report


def write_retrofit_report(target_dir, structured_merges, collision_report):
    """Write .claude-retrofit/REPORT.md describing what the configurator did
    on a retrofit run. Returns the relative path written, or None if the
    report would be empty."""
    if not structured_merges and not collision_report:
        return None
    report_dir = target_dir / ".claude-retrofit"
    report_dir.mkdir(parents=True, exist_ok=True)
    path = report_dir / "REPORT.md"
    skipped = [r for r in collision_report if r["action"] == "skip"]
    renamed = [r for r in collision_report if r["action"] == "rename"]
    overwritten = [r for r in collision_report if r["action"] == "overwrite"]
    lines = ["# Retrofit report",
             "",
             f"Generated by `cc-configure` at {time.strftime('%Y-%m-%dT%H:%M:%S')}.",
             "",
             "Detected existing project files at the target. Structured assets ",
             "(`.claude/settings.json`, `.mcp.json`) were deep-merged in place — "
             "your customizations win on collisions; the configurator's additions "
             "layer on top. File-based assets used the strategy printed below.",
             ""]
    if structured_merges:
        lines.append("## Deep-merged (structured)")
        lines.append("")
        for target_rel, msg in structured_merges:
            lines.append(f"- `{target_rel}` — {msg}")
        lines.append("")
    if skipped:
        identical = [r for r in skipped if r.get("identical")]
        differs = [r for r in skipped if not r.get("identical")]
        if identical:
            lines.append("## Skipped — identical to v2 (safe to drop)")
            lines.append("")
            lines.append("Your file matches the v2 template byte-for-byte. The staged copy is "
                         "redundant — delete it from `.claude-retrofit/incoming/` once you've "
                         "spot-checked. Future-you may also want to delete the original and "
                         "let the next `cc-configure` run write our copy directly.")
            lines.append("")
            lines.append("| Original (yours) | Incoming (identical) |")
            lines.append("|---|---|")
            for r in identical:
                lines.append(f"| `{r['target']}` | `{r['incoming']}` |")
            lines.append("")
        if differs:
            lines.append("## Skipped — differs from v2 (review)")
            lines.append("")
            lines.append("Content diverges from the v2 template. Either you customized the "
                         "file, or v2 evolved the template. Diff each pair to decide.")
            lines.append("")
            lines.append("| Original (yours) | Incoming (v2) |")
            lines.append("|---|---|")
            for r in differs:
                lines.append(f"| `{r['target']}` | `{r['incoming']}` |")
            lines.append("")
    if renamed:
        lines.append("## Renamed (both versions installed side-by-side)")
        lines.append("")
        lines.append("| Yours (untouched) | Ours (installed alongside) |")
        lines.append("|---|---|")
        for r in renamed:
            lines.append(f"| `{r['target']}` | `{r['renamed_to']}` |")
        lines.append("")
    if overwritten:
        lines.append("## Overwritten (yours backed up; ours installed)")
        lines.append("")
        lines.append("| Path (replaced) | Backup |")
        lines.append("|---|---|")
        for r in overwritten:
            lines.append(f"| `{r['target']}` | `{r['backup']}` |")
        lines.append("")
    lines.append("## Next steps")
    lines.append("")
    if skipped:
        lines.append("1. Diff each `Skipped` pair. `diff` for one-shot, your editor for richer review.")
        lines.append("2. Decide per-file: keep yours, replace with ours, or merge sections.")
        lines.append("3. After resolving, delete `.claude-retrofit/` to clear the staging area.")
    if renamed:
        lines.append(f"{'4' if skipped else '1'}. The renamed entries are usable immediately. If you decide you want ours as the canonical, rename the existing file out of the way and rename the `-cc` version into place.")
    lines.append("")
    lines.append("Run `claude` in this project and invoke `/retrofit` to walk this report interactively — the skill ships under `.claude/skills/retrofit/` (or staged at `.claude-retrofit/incoming/.claude/skills/retrofit/SKILL.md` if it collided).")
    path.write_text("\n".join(lines), encoding="utf-8")
    return ".claude-retrofit/REPORT.md"




def check_hook_weight(settings: dict) -> list:
    """Flag hooks on high-frequency events whose command starts with a heavy
    interpreter. These add hundreds of ms per tool call and degrade the session.
    Cheap wrappers (shell scripts, native binaries) are preferred."""
    warnings = []
    for event in HIGH_FREQ_HOOK_EVENTS:
        for group in settings.get("hooks", {}).get(event, []) or []:
            for hook in group.get("hooks", []) or []:
                cmd = (hook.get("command") or "").strip()
                if not cmd:
                    continue
                first = cmd.split(None, 1)[0].strip('"\'')
                base = first.rsplit("/", 1)[-1]
                if base in HEAVY_INTERPRETERS:
                    matcher = group.get("matcher", "") or "(any)"
                    warnings.append(f"{event} [{matcher}]: '{base}' as entrypoint — {cmd}")
    return warnings


def compute_mcp_json(form_values: dict) -> str:
    # Versions pinned via Sonatype MCP (getRecommendedComponentVersions).
    # Bump these as upstream moves; --check will catch structural drift but
    # cannot verify whether a version is current. Run the lookup periodically
    # and update the dict below.
    servers = {}
    if form_values.get("mcp_filesystem"):
        servers["filesystem"] = {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-filesystem@2026.1.14", "."]
        }
    if form_values.get("mcp_git"):
        servers["git"] = {
            "command": "uvx",
            "args": ["--from", "mcp-server-git==2026.1.14", "mcp-server-git",
                     "--repository", "."]
        }
    if form_values.get("mcp_github"):
        # The original @modelcontextprotocol/server-github npm package is
        # end-of-life per Sonatype; upstream removed it from the
        # modelcontextprotocol/servers repo. GitHub now ships an official
        # remote HTTP MCP at api.githubcopilot.com/mcp/. Requires a GitHub
        # PAT in GITHUB_TOKEN (or use OAuth via `claude mcp add` instead).
        servers["github"] = {
            "type": "http",
            "url": "https://api.githubcopilot.com/mcp/",
            "headers": {"Authorization": "Bearer ${GITHUB_TOKEN}"}
        }
    if form_values.get("mcp_playwright"):
        servers["playwright"] = {
            "command": "npx",
            "args": ["-y", "@playwright/mcp@0.0.70"]
        }
    if form_values.get("mcp_context7"):
        servers["context7"] = {
            "command": "npx",
            "args": ["-y", "@upstash/context7-mcp@2.1.8"]
        }
    return json.dumps({"mcpServers": servers}, indent=2) + "\n"


def collect_files(form_values: dict, selected: set, module_flags: dict = None) -> tuple:
    if module_flags is None:
        module_flags = {}
    files = []
    gitignore_lines = []
    placeholders = compute_placeholders(form_values, selected, module_flags)

    for m in MODULES:
        if m["id"] not in selected:
            continue
        # Compute filterPaths allowlist for this module (if any flag selects one).
        flag_values = (module_flags or {}).get(m["id"], {})
        filter_for_module = None
        for flag_name, flag_def in m.get("flags", {}).items():
            selected_value = flag_values.get(flag_name, flag_def["default"])
            fp = flag_def.get("filterPaths", {}).get(selected_value)
            if fp is not None:
                filter_for_module = set(fp)
        for rel in m["paths"]:
            if filter_for_module is not None and rel not in filter_for_module:
                continue
            tgt = target_path_for(rel)
            if not tgt:
                continue
            if tgt == ".claude/settings.json":
                continue  # merged below
            if tgt == ".mcp.json":
                continue  # generated below
            src = TEMPLATE_DIR / rel
            content = src.read_text(encoding="utf-8")
            if "{{" in content:
                content = substitute_placeholders(content, placeholders)
            files.append({
                "target": tgt,
                "content": content,
                "executable": rel.endswith(".sh"),
            })
        # Apply per-flag extraPaths.
        for flag_name, flag_def in m.get("flags", {}).items():
            selected_value = module_flags.get(m["id"], {}).get(flag_name, flag_def["default"])
            for rel in flag_def.get("extraPaths", {}).get(selected_value, []):
                tgt = target_path_for(rel)
                if not tgt:
                    continue
                if tgt == ".claude/settings.json":
                    continue
                if tgt == ".mcp.json":
                    continue
                src = TEMPLATE_DIR / rel
                content = src.read_text(encoding="utf-8")
                if "{{" in content:
                    content = substitute_placeholders(content, placeholders)
                files.append({
                    "target": tgt,
                    "content": content,
                    "executable": rel.endswith(".sh"),
                })
        if m.get("gitignoreSource"):
            gi = (TEMPLATE_DIR / m["gitignoreSource"]).read_text(encoding="utf-8").splitlines()
            gitignore_lines.extend(gi)

    files.append({
        "target": ".claude/settings.json",
        "content": json.dumps(compute_merged_settings(form_values, selected, module_flags), indent=2) + "\n",
        "executable": False,
    })
    if "mcp" in selected:
        files.append({
            "target": ".mcp.json",
            "content": compute_mcp_json(form_values),
            "executable": False,
        })
    return files, gitignore_lines


# -----------------------------------------------------------------------------
# File application (actual writes to target directory)
# -----------------------------------------------------------------------------
def apply_files(files, gitignore_lines, target_dir: Path, dry_run=False, backup=True):
    target_dir = target_dir.resolve()
    if not target_dir.exists():
        target_dir.mkdir(parents=True)
    if target_dir == Path.home() or target_dir == Path("/"):
        raise SystemExit(red("Refusing to scaffold in $HOME or /."))

    timestamp = time.strftime("%Y%m%d%H%M%S")
    written, backed_up = [], []

    for f in files:
        dest = target_dir / f["target"]
        if dry_run:
            written.append(f["target"] + (" (would overwrite)" if dest.exists() else ""))
            continue
        if dest.exists() and backup:
            bak = dest.with_suffix(dest.suffix + f".bak-{timestamp}")
            shutil.copy2(dest, bak)
            backed_up.append(str(bak.relative_to(target_dir)))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(f["content"], encoding="utf-8")
        if f["executable"]:
            mode = dest.stat().st_mode
            dest.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        written.append(f["target"])

    gi_added = False
    if gitignore_lines and not dry_run:
        gi_path = target_dir / ".gitignore"
        existing = gi_path.read_text(encoding="utf-8") if gi_path.exists() else ""
        if "# --- Claude Code ---" not in existing:
            with gi_path.open("a", encoding="utf-8") as fh:
                if existing and not existing.endswith("\n"):
                    fh.write("\n")
                fh.write("\n" + "\n".join(gitignore_lines) + "\n")
            gi_added = True

    return {"written": written, "backed_up": backed_up, "gitignore_added": gi_added}


# -----------------------------------------------------------------------------
# Interactive prompts
# -----------------------------------------------------------------------------
def _input(prompt: str) -> str:
    try:
        return input(prompt)
    except EOFError:
        return ""


def prompt_text(field, current):
    label = field["label"]
    default = current if current is not None else field["default"]
    val = _input(f"  {label} [{dim(str(default))}]: ").strip()
    return val if val else default


def prompt_select(field, current):
    """Select prompt with three input modes:
      - Numeric (1-N): pick by index.
      - Text prefix: case-insensitive prefix match of the option text (`REST`,
        `graph…`, `post…` → first matching option).
      - Custom free text: only when the field sets `allow_custom: True`. Any
        input that isn't a number or prefix match is accepted verbatim as the
        value. Without the flag, unmatched input falls back to the default
        (guards against typos).
    """
    label = field["label"]
    options = field["options"]
    default = current if current in options else field["default"]
    allow_custom = field.get("allow_custom", False)
    print(f"  {label}")
    for i, opt in enumerate(options, 1):
        marker = "*" if opt == default else " "
        print(f"    {marker} {i}) {opt}")
    if allow_custom:
        print(dim("       *) or type your own value"))
        suffix = (f"  Pick 1-{len(options)}, type an option name, type a custom value, "
                  f"or Enter for default [{dim(default)}]: ")
    else:
        suffix = (f"  Pick 1-{len(options)} or type an option name "
                  f"(prefix match); Enter for default [{dim(default)}]: ")
    raw = _input(suffix).strip()
    if not raw:
        return default
    if raw.isdigit() and 1 <= int(raw) <= len(options):
        return options[int(raw) - 1]
    # Case-insensitive prefix match
    for opt in options:
        if opt.lower().startswith(raw.lower()):
            return opt
    # No match — branch on allow_custom
    if allow_custom:
        print(dim(f"    (using custom value: {raw})"))
        return raw
    print(yellow(f"    (didn't match, keeping {default})"))
    return default


def prompt_checkbox(field, current):
    label = field["label"]
    default = current if isinstance(current, bool) else field["default"]
    default_char = "Y/n" if default else "y/N"
    raw = _input(f"  {label} [{dim(default_char)}]: ").strip().lower()
    if not raw:
        return default
    if raw in ("y", "yes", "true", "1"):
        return True
    if raw in ("n", "no", "false", "0"):
        return False
    return default


def prompt_textarea(field, current):
    label = field["label"]
    default = current if current else field["default"]
    print(f"  {label}")
    print(dim(f"    (current: {default.splitlines()[0][:60]}...)") if default else "")
    print(dim("    Enter lines. Empty line to finish. 'keep' to keep current. 'clear' for blank."))
    first = _input(f"    > ").strip()
    if first == "" and default:
        return default  # keep
    if first.lower() == "keep":
        return default
    if first.lower() == "clear":
        return ""
    lines = [first] if first else []
    while True:
        line = _input(f"    > ")
        if line == "":
            break
        lines.append(line)
    return "\n".join(lines)


def apply_stack_preset(form_values: dict):
    """If stack_preset is set to a real preset, copy its values into form_values.
    Called inline right after stack_preset is prompted so downstream stack/commands
    fields see the preset values as their defaults."""
    preset = form_values.get("stack_preset")
    overrides = STACK_PRESETS.get(preset)
    if not overrides:
        return  # "Custom / keep current" or unknown -> no-op
    form_values.update(overrides)


def prompt_section(section, form_values):
    print()
    print(bold(blue(f"[ {section['title'].upper()} ]")))
    for f in section["fields"]:
        if f.get("help"):
            print(dim(f"  \u2192 {f['help']}"))
        key = f["key"]
        prev = form_values.get(key)
        cur = prev
        t = f["type"]
        if t == "text":
            form_values[key] = prompt_text(f, cur)
        elif t == "select":
            form_values[key] = prompt_select(f, cur)
        elif t == "checkbox":
            form_values[key] = prompt_checkbox(f, cur)
        elif t == "textarea":
            form_values[key] = prompt_textarea(f, cur)
        # Chained choices: when a trigger field's value changes, recompute
        # defaults for downstream fields BEFORE they are prompted.
        if form_values[key] != prev:
            if key == "stack_preset":
                apply_stack_preset(form_values)
            elif key == "efficiency_preset":
                apply_preset(form_values)


def apply_preset(form_values: dict):
    """If efficiency_preset changed from a preset, flip the dependent toggles."""
    p = form_values.get("efficiency_preset", "")
    if "Aggressive" in p:
        form_values.update({
            "eff_scoped_reads": True, "eff_grep_over_cat": True,
            "eff_bash_narrowing": True, "eff_reset_rhythm": True,
            "eff_plan_mode": True, "eff_haiku_first": True,
            "eff_effort_minimal": True, "eff_desc_budget": True,
            "eff_bash_max_lines": "40",
        })
    elif "Relaxed" in p:
        form_values.update({
            "eff_scoped_reads": False, "eff_grep_over_cat": False,
            "eff_bash_narrowing": False, "eff_reset_rhythm": False,
            "eff_plan_mode": True, "eff_haiku_first": False,
            "eff_effort_minimal": False, "eff_desc_budget": False,
            "eff_bash_max_lines": "disabled",
        })
    else:  # Balanced
        form_values.update({
            "eff_scoped_reads": True, "eff_grep_over_cat": True,
            "eff_bash_narrowing": True, "eff_reset_rhythm": True,
            "eff_plan_mode": True, "eff_haiku_first": True,
            "eff_effort_minimal": True, "eff_desc_budget": True,
            "eff_bash_max_lines": "80",
        })


def prompt_modules(selected: set):
    print()
    print(bold(blue("[ MODULES ]")))
    print(dim("  Toggle each module. Required modules can't be disabled."))
    for m in MODULES:
        if m.get("required"):
            print(f"  {green('[X]')} {bold(m['title'])} {dim('(required)')}")
            continue
        is_on = m["id"] in selected
        marker = green("[X]") if is_on else "[ ]"
        desc_short = m["description"].split(".")[0][:70]
        print(f"  {marker} {bold(m['title'])}")
        print(f"      {dim(desc_short)}")
        default_char = "Y/n" if is_on else "y/N"
        raw = _input(f"      include? [{dim(default_char)}]: ").strip().lower()
        if not raw:
            pass  # keep current
        elif raw in ("y", "yes"):
            selected.add(m["id"])
        elif raw in ("n", "no"):
            selected.discard(m["id"])
    return selected


def quick_interactive(target_dir: Path, initial: dict, skip_persona_q: bool = False) -> dict:
    """5-question happy-path intake. Persona drives module/flag/form defaults.

    `skip_persona_q` is set by the v1-NOTICE branch in main(), which has
    already prompted for persona and applied its modules/flags/form defaults.
    Re-prompting from quick_interactive in that case shows the menu twice
    AND would replace (not union) the user's pre-existing module set."""
    print(bold("=" * 60))
    print(bold("  Claude Code project configurator \u2014 quick mode"))
    print(bold("=" * 60))
    print(f"  Target: {green(str(target_dir.resolve()))}")
    print(dim("  5 questions; documentation fields use [TODO:] placeholders."))
    print(dim("  Use --detailed for the full intake. Ctrl+C to abort."))
    print()

    if not skip_persona_q:
        # Q1: persona
        persona = _ask_persona(initial.get("persona", "solo-newer"))
        pmods, pflags = pick_persona_modules(persona)
        initial["persona"] = persona
        initial["selected"] = pmods
        initial.setdefault("module_flags", {})
        for mid, fkv in pflags.items():
            initial["module_flags"].setdefault(mid, {}).update(fkv)
        apply_persona_defaults(persona, initial["formValues"])
        inject_placeholders(initial["formValues"], persona)

    # Q2: project name
    fv = initial["formValues"]
    fv["project_name"] = _input(f"  Project name [{fv.get('project_name', target_dir.name)}]: ").strip() or fv.get("project_name", target_dir.name)

    # Q3: stack preset
    stack_keys = list(STACK_PRESETS.keys())
    print("  Stack preset:")
    for i, sk in enumerate(stack_keys, 1):
        print(f"    {i}) {sk}")
    raw = _input(f"  pick [1-{len(stack_keys)}, default={stack_keys.index(fv.get('stack_preset', _DEFAULT_STACK)) + 1}]: ").strip()
    if raw.isdigit() and 1 <= int(raw) <= len(stack_keys):
        fv["stack_preset"] = stack_keys[int(raw) - 1]
    apply_stack_preset(fv)

    # Q4: repo url (optional). Empty default is intentional — a [TODO:]
    # placeholder gets stamped later by normalize_conditional_placeholders.
    fv["repo_url"] = _input(
        f"  Repo URL (optional, e.g. git@github.com:owner/repo.git) "
        f"[{fv.get('repo_url', '')}]: "
    ).strip() or fv.get("repo_url", "")

    # Q5: license
    fv["license"] = _input(f"  License [{fv.get('license', 'MIT')}]: ").strip() or fv.get("license", "MIT")

    return initial


def _ask_persona(default: str) -> str:
    print("  Persona \u2014 pick a sensible kit, then we ask 4 follow-ups:")
    keys = list(PERSONAS.keys())
    for i, k in enumerate(keys, 1):
        p = PERSONAS[k]
        marker = green("→") if k == default else " "
        print(f"   {marker} {i}) {bold(k):20} {dim(p['title'])}")
    raw = _input(f"  pick [1-{len(keys)}, default={keys.index(default) + 1}]: ").strip()
    if raw.isdigit() and 1 <= int(raw) <= len(keys):
        return keys[int(raw) - 1]
    return default


def interactive(target_dir: Path, initial: dict) -> dict:
    print(bold("=" * 60))
    print(bold("  Claude Code project configurator \u2014 CLI"))
    print(bold("=" * 60))
    print(f"  Target: {green(str(target_dir.resolve()))}")
    if (target_dir / ".claude-config.json").exists():
        print(f"  {dim('(loaded existing .claude-config.json)')}")
    print()
    print(dim("  Press Enter to accept the default shown in [brackets]."))
    print(dim("  Ctrl+C at any time to abort."))

    form_values = initial["formValues"]
    selected = initial["selected"]

    # Chained-choice triggers (stack_preset, efficiency_preset) fire inline
    # inside prompt_section when the field's value changes.
    for section in FORM_SCHEMA:
        prompt_section(section, form_values)

    selected = prompt_modules(selected)
    return {"formValues": form_values, "selected": selected}


# -----------------------------------------------------------------------------
# Legacy module translator
# -----------------------------------------------------------------------------
LEGACY_MODULE_MAP = {
    "lockdown": ("safety", {"lockdown": True}),
    "token-efficiency-pro": ("token-efficiency", {"tier": "pro"}),
    "commands-core": ("commands", {"subset": "full"}),
    "agents": ("commands", {}),  # agents alone is a no-op flag; adds commands module
}


def translate_legacy_modules(wanted: set, current_flags: dict) -> tuple:
    """Returns (new_module_set, updated_flags, deprecation_messages).

    Translates legacy module IDs into their modern equivalents, updating
    module_flags as needed. Used by --modules arg handling. The deprecation
    messages are stored on initial["_deprecations"] and rendered in the
    [ DEPRECATED ] block (added by Task 6).
    """
    out_modules = set()
    out_flags = dict(current_flags)
    deprecations = []
    for mid in wanted:
        if mid in LEGACY_MODULE_MAP:
            new_id, flag_kv = LEGACY_MODULE_MAP[mid]
            out_modules.add(new_id)
            out_flags.setdefault(new_id, {}).update(flag_kv)
            # Suppress trailing parens when no flags are set (e.g. legacy
            # `agents` maps to `commands` with empty flag_kv — the bare
            # rename has no flag suffix to show).
            if flag_kv:
                kv_suffix = " ({})".format(
                    ", ".join("{}={}".format(k, v) for k, v in flag_kv.items())
                )
            else:
                kv_suffix = ""
            deprecations.append(
                "--modules {}  →  --modules {}{}".format(mid, new_id, kv_suffix)
            )
        else:
            out_modules.add(mid)
    return out_modules, out_flags, deprecations


# -----------------------------------------------------------------------------
# CLI entry
# -----------------------------------------------------------------------------
def parse_args():
    p = argparse.ArgumentParser(
        description="Scaffold Claude Code project setup from an intake form + module picker.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--dir", default=".", help="Target project directory (default: .)")
    p.add_argument("--config", help="Load config from a JSON file instead of prompting")
    p.add_argument("--save-config", help="Write the resulting config to this path (does nothing else unless combined with other flags)")
    p.add_argument("--save-config-only", help="Write the config and exit without scaffolding")
    p.add_argument("--preset", choices=["balanced", "aggressive", "relaxed"],
                   help="Non-interactive: apply an efficiency preset")
    p.add_argument("--persona", choices=list(PERSONAS.keys()),
                   help="Pre-pick modules + flags + form defaults for a persona. "
                        "Combine with --yes for fully non-interactive scaffolding. "
                        "Use 'custom' for the v1 explicit-field flow.")
    p.add_argument("--detailed", action="store_true",
                   help="Use the full 50-field intake (v1 behavior). Default flow asks 5 questions.")
    p.add_argument("--modules", help="Non-interactive: comma-separated module IDs to enable")
    p.add_argument("--yes", action="store_true",
                   help="Non-interactive: accept all defaults (combine with --preset / --modules to override)")
    p.add_argument("--dry-run", action="store_true", help="Show what would be written and exit")
    p.add_argument("--no-backup", action="store_true", help="Don't back up existing files")
    p.add_argument("--force", action="store_true",
                   help="Equivalent to --on-collision=overwrite AND skip the deep-"
                        "merge of structured assets. Forces a clean install: every "
                        "existing target file is replaced (originals back up to "
                        "*.bak-<ts> unless --no-backup is also set).")
    p.add_argument("--on-collision", choices=["skip", "overwrite", "rename"],
                   default="skip",
                   help="How to handle collisions on file-based assets (skills, "
                        "agents, rules, hooks): skip stages our version "
                        "to .claude-retrofit/incoming/ for manual review (default); "
                        "overwrite replaces yours with .bak-<ts>; rename installs "
                        "ours at a -cc-suffixed sibling so both coexist. Structured "
                        "assets (.claude/settings.json, .mcp.json) are always deep-"
                        "merged regardless of this flag (unless --force). "
                        "CLAUDE.md uses --claude-md instead.")
    p.add_argument("--claude-md", choices=["append", "skip", "overwrite"],
                   default="append",
                   help="How to handle a collision on CLAUDE.md specifically. "
                        "append (default): merge our value-add sections "
                        "('## Working with Claude', '## Claude Code behavior rules', "
                        "'## Token efficiency rules') into your existing CLAUDE.md, "
                        "preserving everything else; idempotent on re-runs. skip: "
                        "stage ours to .claude-retrofit/incoming/CLAUDE.md, leave "
                        "yours untouched. overwrite: replace yours with .bak-<ts>.")
    p.add_argument("--check", action="store_true",
                   help="Static validation of templates + MODULES registry (CI-friendly). "
                        "Exits 0 on clean, 1 with a per-issue summary otherwise. "
                        "Skips all other processing — no scaffolding, no prompts.")
    return p.parse_args()


def main():
    args = parse_args()
    # --check short-circuits everything else: no scaffolding, no target dir creation.
    if args.check:
        sys.exit(run_check())
    target_dir = Path(args.dir).resolve()
    target_dir.mkdir(parents=True, exist_ok=True)
    saved_config_path = target_dir / ".claude-config.json"

    # --- determine starting values ---
    # Precedence: --config flag > saved .claude-config.json > defaults.
    # CLI overrides (--preset, --modules) are applied on top below.
    if args.config:
        initial = load_config(Path(args.config))
    elif saved_config_path.exists():
        initial = load_config(saved_config_path)
    else:
        initial = {"formValues": default_form_values(), "selected": default_selected()}

    # Snapshot the user's pre-persona module_flags so we can show what got
    # overridden by the persona's flag picks in the [ APPLIED ] block.
    initial["_pre_persona_flags"] = {
        mid: dict(fkv) for mid, fkv in initial.get("module_flags", {}).items()
    }

    # v1-config upgrade: a one-time interactive prompt offers a persona pick
    # when an existing .claude-config.json predates schema_version=2. Bypassed
    # by every non-interactive path so script callers' behavior is unchanged.
    is_v1_config = (
        saved_config_path.exists()
        and initial.get("schema_version", 1) < 2
        and not args.yes
        and not args.persona
        and not args.detailed
        and not args.config
        and not args.modules
        and not args.save_config_only
    )
    if is_v1_config:
        print()
        print(bold(yellow("[ NOTICE ]")), "Persona-based defaults are new in v2.0.")
        print("           Pick one to simplify future re-runs, or 'custom' to keep")
        print("           your current granular config.")
        suggested = infer_persona(initial.get("selected", set()),
                                  initial.get("module_flags", {}))
        chosen = _ask_persona(suggested)
        initial["persona"] = chosen
        initial["schema_version"] = 2
        if chosen != "custom":
            pmods, pflags = pick_persona_modules(chosen)
            initial["selected"] = set(initial.get("selected", set())) | pmods
            initial.setdefault("module_flags", {})
            for mid, fkv in pflags.items():
                initial["module_flags"].setdefault(mid, {}).update(fkv)
            apply_persona_defaults(chosen, initial["formValues"])
            inject_placeholders(initial["formValues"], chosen)

    # --- apply CLI flags ---
    # --persona runs first so explicit --modules / --preset / form fields can override.
    if args.persona:
        pmods, pflags = pick_persona_modules(args.persona)
        initial["selected"] = pmods
        initial.setdefault("module_flags", {})
        for mid, fkv in pflags.items():
            initial["module_flags"].setdefault(mid, {}).update(fkv)
        initial["persona"] = args.persona
        apply_persona_defaults(args.persona, initial["formValues"])
        inject_placeholders(initial["formValues"], args.persona)
    if args.preset:
        pmap = {"balanced": "Balanced (recommended)",
                "aggressive": "Aggressive (haiku-first, strict caps)",
                "relaxed": "Relaxed (correctness over cost)"}
        initial["formValues"]["efficiency_preset"] = pmap[args.preset]
        apply_preset(initial["formValues"])
        # --preset is being phased out; surface the migration in [ DEPRECATED ].
        new_tier = "pro" if args.preset == "aggressive" else "basic"
        initial.setdefault("_deprecations", []).append(
            "--preset {}  →  --token-efficiency-tier={} "
            "(--preset will be removed in v3.0)".format(args.preset, new_tier)
        )
    if args.modules:
        wanted = {m.strip() for m in args.modules.split(",") if m.strip()}
        wanted, initial["module_flags"], deprecations = translate_legacy_modules(
            wanted, initial.get("module_flags", {})
        )
        initial["selected"] = wanted | {m["id"] for m in MODULES if m.get("required")}
        # Stored here; rendered as [ DEPRECATED ] block in Task 6.
        initial.setdefault("_deprecations", []).extend(deprecations)

    # --- interactive if needed ---
    # --yes / --config / --modules / --persona / --preset / --save-config-only:
    # skip interactive entirely (preserves v1 non-interactive paths).
    # --detailed: opt back into the full v1 50-field interactive() flow.
    # default (no flags): quick 5-question mode via quick_interactive().
    if args.yes or args.config or args.preset or args.modules or args.persona or args.save_config_only:
        config = initial
    elif args.detailed:
        config = interactive(target_dir, initial)
    else:
        # When the v1-NOTICE branch already prompted for a persona, skip Q1
        # in quick_interactive so the menu doesn't appear twice.
        config = quick_interactive(target_dir, initial, skip_persona_q=is_v1_config)

    # Resolve any declared module dependencies before saving or scaffolding,
    # so we never generate an inconsistent set.
    config["selected"] = resolve_dependencies(config["selected"])

    # --- save-config flow ---
    if args.save_config_only:
        save_config(config, Path(args.save_config_only))
        print(green(f"Wrote config to {args.save_config_only}"))
        return
    if args.save_config:
        save_config(config, Path(args.save_config))
        print(dim(f"(also saved config to {args.save_config})"))

    # --- scaffold ---
    # Value-conditional placeholder stamping (currently `repo_url`). Runs
    # after every form-input path so [ PLACEHOLDERS ] catches "unset" fields
    # regardless of whether the user came in via --yes / --persona / --quick.
    normalize_conditional_placeholders(config["formValues"])

    files, gitignore_lines = collect_files(config["formValues"], config["selected"], config.get("module_flags", {}))

    # Pre-flight: surface version mismatches, schema drift, heavy hooks,
    # and module prerequisites before writing any files.
    version_warnings = check_claude_code_version()
    if version_warnings:
        print()
        print(bold(yellow("[ VERSION WARNINGS ]")))
        for w in version_warnings:
            print(f"  {yellow('!')} {w}")

    merged = compute_merged_settings(config["formValues"], config["selected"], config.get("module_flags", {}))
    schema_warnings = check_schema_url(merged)
    if schema_warnings:
        print()
        print(bold(yellow("[ SCHEMA WARNINGS ]")))
        for w in schema_warnings:
            print(f"  {yellow('!')} {w}")

    hook_warnings = check_hook_weight(merged)
    if hook_warnings:
        print()
        print(bold(yellow("[ HOOK WARNINGS ]")))
        for w in hook_warnings:
            print(f"  {yellow('!')} {w}")
        print(dim("  Heavy interpreters on high-frequency events add hundreds of ms per tool call."))
        print(dim("  Prefer .sh wrappers or native binaries when attaching to PreToolUse/PostToolUse."))

    # Surface module-level prerequisites that can't be fixed by the configurator.
    module_warnings = []
    if "github-actions" in config["selected"]:
        for w in check_github_remote(target_dir):
            module_warnings.append(("github-actions", w))
    if module_warnings:
        print()
        print(bold(yellow("[ MODULE WARNINGS ]")))
        for mod, w in module_warnings:
            print(f"  {yellow('!')} {mod}: {w}")

    # Surface MCP/agent env-var prerequisites that aren't set in the user's
    # shell. Non-blocking — the templates still write; the auth tokens just
    # need to be exported before `claude` is launched.
    env_warnings = check_mcp_env_vars(config["formValues"], config["selected"])
    if env_warnings:
        print()
        print(bold(yellow("[ ENV WARNINGS ]")))
        for w in env_warnings:
            print(f"  {yellow('!')} {w}")

    # Surface pre-existing design docs (typical output of a prior superpowers
    # brainstorming session). Informational, not a warning — the install is
    # fine; we just want to nudge the user to fold their design into CLAUDE.md
    # instead of letting the generic template stand.
    deprecations = check_deprecations(initial.get("_deprecations", []))
    if deprecations:
        print()
        print(bold(yellow("[ DEPRECATED ]")))
        for d in deprecations:
            print(f"  {yellow('!')} {d}")

    overrides = detect_persona_overrides(
        initial.get("_pre_persona_flags", {}),
        initial.get("persona", "custom"),
    )
    applied = render_applied_block(
        initial.get("persona", "custom"),
        config["selected"],
        config.get("module_flags", {}),
        overrides=overrides,
    )
    print()
    print(bold(blue("[ APPLIED ]")))
    for line in applied:
        print(f"  {line}")

    placeholders = check_placeholders(config["formValues"])
    if placeholders:
        print()
        print(bold(yellow("[ PLACEHOLDERS ]")))
        for field, excerpt in placeholders:
            print(f"  {yellow('!')} CLAUDE.md (field={field}) — {dim(excerpt)}")

    next_steps = []
    if placeholders:
        next_steps.append("Edit CLAUDE.md to fill in the [TODO:] placeholders above.")
    if not args.dry_run and not (target_dir / ".git").is_dir():
        next_steps.append(
            "No git repo here yet — `git init -b main && git add . && "
            "git commit -m 'chore: cc-configure scaffold'`. The Claude Code "
            ".gitignore block already excludes machine-local / transient files; "
            "see CLAUDE.md `### Repo bootstrap` for what to track."
        )
    persona = initial.get("persona", "custom")
    if persona == "solo-newer":
        next_steps.append(
            "Want a fuller kit? Re-run with `--persona solo-experienced` or `--detailed`."
        )
    if initial.get("_deprecations"):
        next_steps.append(
            "Legacy flags used — see [ DEPRECATED ] above for the v3.0 migration."
        )
    if next_steps:
        print()
        print(bold(blue("[ NEXT STEPS ]")))
        for s in next_steps:
            print(f"  {blue('→')} {s}")

    design_docs = check_design_docs(target_dir)
    if design_docs:
        print()
        print(bold(blue("[ DESIGN DETECTED ]")))
        for path in design_docs[:5]:
            print(f"  {blue('i')} {path}")
        if len(design_docs) > 5:
            print(dim(f"      … and {len(design_docs) - 5} more"))
        print(dim("  CLAUDE.md will be written from your form answers (generic template)."))
        print(dim("  After scaffolding, fold project-wide invariants from the design"))
        print(dim("  doc(s) into CLAUDE.md. See Next steps below."))

    print()
    print(bold(blue("[ SUMMARY ]")))
    print(f"  Target : {green(str(target_dir))}")
    print(f"  Modules: {', '.join(sorted(config['selected']))}")
    print(f"  Files  : {len(files)} ({sum(1 for f in files if f['executable'])} executable)")
    if gitignore_lines:
        rules = [l.strip() for l in gitignore_lines if l.strip() and not l.startswith('#')]
        if len(rules) <= 5:
            sample = ", ".join(rules)
        else:
            sample = ", ".join(rules[:3]) + f", … and {len(rules) - 3} more"
        print(f"  .gitignore: append {len(rules)} rules ({sample})")

    # Retrofit Tier 2: structured-asset deep-merge + file-collision strategy.
    # --force short-circuits both — every existing file is overwritten with
    # .bak-<ts> (the pre-Tier-2 behavior, kept as a kill-switch).
    if args.force:
        merge_messages = []
        collision_report = []
    else:
        merge_messages = apply_structured_merges(files, target_dir)
        # CLAUDE.md gets its own strategy — append-valueadd by default.
        cm_merge, cm_collision, files = apply_claudemd_strategy(
            files, target_dir, args.claude_md)
        if cm_merge is not None:
            merge_messages.append(cm_merge)
        # Other file-based collisions (skills, agents, rules, hooks).
        files, collision_report = apply_file_collision_strategy(
            files, target_dir, args.on_collision)
        if cm_collision is not None:
            collision_report.append(cm_collision)

    # Surface what we did to existing files before writes (or in the dry-run
    # output). Both blocks are silent on a clean greenfield install.
    if merge_messages:
        # Pull the colored tick out of the f-string — Python 3.11 forbids
        # backslashes in f-string expressions (3.12+ relaxed this).
        tick = green("✓")
        print()
        print(bold(blue("[ MERGED ]")))
        for target_rel, msg in merge_messages:
            print(f"  {tick} {target_rel} — {msg}")

    if collision_report:
        print()
        action_label = {"skip": "skipped (yours preserved, ours staged)",
                        "rename": "renamed (both installed side-by-side)",
                        "overwrite": "overwritten (yours backed up)"}
        # Group by action for cleaner output.
        by_action = {}
        for r in collision_report:
            by_action.setdefault(r["action"], []).append(r)
        print(bold(blue("[ COLLISIONS ]")))
        for action, entries in by_action.items():
            print(f"  {len(entries)} file(s) {action_label.get(action, action)}:")
            for r in entries[:10]:
                if action == "skip":
                    print(f"    {dim('-')} {r['target']} -> {r['incoming']}")
                elif action == "rename":
                    print(f"    {dim('-')} {r['target']} -> {r['renamed_to']}")
                else:
                    print(f"    {dim('-')} {r['target']}")
            if len(entries) > 10:
                print(dim(f"    … and {len(entries) - 10} more"))

    if args.dry_run:
        print()
        print(bold(yellow("[ DRY RUN \u2014 no files written ]")))
        for f in files:
            tag = green('+') if not f.get("was_merged") else blue('~')
            print(f"    {tag} {f['target']}")
        return

    print()
    result = apply_files(files, gitignore_lines, target_dir,
                        dry_run=False, backup=not args.no_backup)
    # Write the retrofit report up-front so its path joins the wrote group
    # rather than landing between backed-up and saved-config lines.
    report_path = write_retrofit_report(target_dir, merge_messages, collision_report)

    # Per-task MCP profile alternates render as a single grouped line so
    # they don't visually crowd the active .mcp.json among regular writes.
    mcp_alts = (".mcp.minimal.json", ".mcp.frontend.json", ".mcp.research.json")
    written_alts = [p for p in result["written"] if str(p) in mcp_alts]
    written_main = [p for p in result["written"] if str(p) not in mcp_alts]

    for p in written_main:
        print(f"    {green('wrote')} {p}")
    if written_alts:
        names = ", ".join(sorted(str(p) for p in written_alts))
        print(f"    {green('wrote')} {len(written_alts)} MCP profile alternates ({names}) — switch via cp")
    if report_path:
        print(f"    {green('wrote')} {report_path}")
    for p in result["backed_up"]:
        print(f"    {yellow('backed up')} {p}")
    if result["gitignore_added"]:
        print(f"    {green('+')} .gitignore (Claude Code block appended)")

    save_config(config, saved_config_path)
    print(dim(f"    saved config to {saved_config_path.relative_to(target_dir)}"))

    print()
    print(green(bold("Done.")))
    print("Next steps:")
    # Context-aware guidance: was this a fresh-project scaffold or a retrofit?
    # Heuristic: if any structured asset was deep-merged or any file was
    # staged/renamed/overwritten, it's a retrofit run. Otherwise fresh.
    is_retrofit = bool(merge_messages) or bool(collision_report)
    if is_retrofit:
        print("  1. Review the [ MERGED ] / [ COLLISIONS ] output above.")
        print("  2. If anything was staged to .claude-retrofit/incoming/, run")
        print(dim("       claude  # then invoke the /retrofit skill"))
        print("     to walk the staged conflicts interactively. See")
        print(dim("     docs/11-getting-started.md and docs/09-retrofit-guide.md."))
        print("  3. Once .claude-retrofit/ is empty, you can delete it.")
        print("  4. Run claude /memory and /context to verify what loaded.")
    elif design_docs:
        primary = design_docs[0]
        print(f"  1. Fold project-wide invariants from {primary} into CLAUDE.md.")
        print(dim("     The configurator's CLAUDE.md is a generic template populated from"))
        print(dim("     your form answers; it doesn't know about your design. Target ~200"))
        print(dim("     lines, project-wide only \u2014 push subsystem-specific guidance to"))
        print(dim("     .claude/rules/<scope>.md with paths: frontmatter."))
        print("  2. Review CLAUDE.md and .claude/settings.json permissions.")
        print("  3. If docs/recommended-plugins.md was generated, install the")
        print("     stack-specific plugins it lists (claude /plugin install <name>).")
        print("  4. Run: claude \u2014 then /memory and /context to check what loaded.")
    else:
        print("  1. If this is a brand-new project, consider design-first brainstorming")
        print("     before implementation:")
        print(dim("       claude /plugin install superpowers"))
        print(dim("       claude  # describe what you want to build \u2014 superpowers"))
        print(dim("                 auto-triggers brainstorming and hard-gates"))
        print(dim("                 implementation until you approve a design"))
        print("     Capture the resulting design to docs/design.md.")
        print("  2. Review CLAUDE.md \u2014 populated from your answers.")
        print("  3. Review .claude/settings.json permissions.")
        print("  4. If docs/recommended-plugins.md was generated, install the")
        print("     stack-specific plugins it lists (claude /plugin install <name>).")
        print("  5. Run: claude \u2014 then /memory and /context to check what loaded.")
    print()
    print(dim("See docs/11-getting-started.md for the full new-project / retrofit walkthroughs."))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
        print("\033[31mAborted.\033[0m" if sys.stdout.isatty() else "Aborted.")
        sys.exit(130)
