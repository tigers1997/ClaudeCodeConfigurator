#!/usr/bin/env python3
"""
cc-configure — CLI for the Claude Code project configurator.
Runs on headless Debian (or anywhere with Python 3.8+). Pure stdlib.

Usage:
  configure.py                              # interactive TUI against current dir
  configure.py --dir /path/to/project       # target a different directory
  configure.py --config .claude-config.json # non-interactive from a saved file
  configure.py --preset balanced \
               --modules core,safety,git-workflow,token-efficiency-pro,commands-core \
               --yes                        # non-interactive with CLI flags
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
        CLAUDE_CODE_COMPAT, MODULES, FORM_SCHEMA, STACK_PRESETS, target_path_for,
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
    selected.update({"safety", "git-workflow", "commands-core", "agents",
                     "token-efficiency", "token-efficiency-pro"})
    return resolve_dependencies(selected)


def resolve_dependencies(selected: set) -> set:
    """Expand `selected` to include every module's transitive `dependsOn`.
    Keeps users from ending up with e.g. commands-core selected but agents
    deselected, which would leave /review pointing at a missing subagent."""
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
    data = json.loads(path.read_text(encoding="utf-8"))
    values = default_form_values()
    values.update(data.get("formValues", {}))
    selected = set(data.get("selected", default_selected()))
    return {"formValues": values, "selected": selected}


def save_config(config: dict, path: Path):
    out = {
        "formValues": config["formValues"],
        "selected": sorted(config["selected"]),
        "_version": 1,
    }
    path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")


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


def build_efficiency_rules(v: dict) -> str:
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
    if not rules:
        return ""
    return "## Token efficiency rules\n\n" + "\n".join(rules)


def compute_placeholders(form_values: dict, selected: set) -> dict:
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
    v["efficiency_rules"] = build_efficiency_rules(form_values)
    # Lightweight skills (check-context, sync-docs, session-retro) carry an
    # {{effort_frontmatter}} slot. When the user opts into "effort: minimal
    # on simple skills", stamp it; otherwise leave the slot empty so the
    # next line follows directly.
    v["effort_frontmatter"] = (
        "effort: minimal\n" if form_values.get("eff_effort_minimal") else ""
    )
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


def compute_merged_settings(form_values: dict, selected: set) -> dict:
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

    if form_values.get("default_model"):
        settings["model"] = form_values["default_model"]

    if "token-efficiency-pro" in selected and form_values.get("eff_bash_max_lines"):
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

    # --- 2. Static file checks: walk templates/ once ---
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
            rel.parts and rel.parts[0] in ("agents",) and f.suffix == ".md"
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


def check_retrofit_state(files, target_dir):
    """Detect files in `files` that already exist at `target_dir`.
    Returns a list of (target_relative_path, absolute_path) tuples.
    Empty list = greenfield install, safe to proceed.

    Tier 1 of retrofit safety: just detect collisions. Default behavior at
    the call site is to refuse to proceed unless --force is passed; .bak-<ts>
    fallback still applies when --force is in effect. Tier 2 will add deep-
    merge for structured assets (settings.json, .mcp.json) and skip-and-stage
    for file collisions (skills/agents/rules/hooks). Tier 3 will add the
    /retrofit skill that walks the staged report interactively."""
    collisions = []
    for f in files:
        dest = target_dir / f["target"]
        if dest.exists():
            collisions.append((f["target"], dest))
    return collisions


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


def collect_files(form_values: dict, selected: set):
    files = []
    gitignore_lines = []
    placeholders = compute_placeholders(form_values, selected)

    for m in MODULES:
        if m["id"] not in selected:
            continue
        for rel in m["paths"]:
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
        if m.get("gitignoreSource"):
            gi = (TEMPLATE_DIR / m["gitignoreSource"]).read_text(encoding="utf-8").splitlines()
            gitignore_lines.extend(gi)

    files.append({
        "target": ".claude/settings.json",
        "content": json.dumps(compute_merged_settings(form_values, selected), indent=2) + "\n",
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
    p.add_argument("--modules", help="Non-interactive: comma-separated module IDs to enable")
    p.add_argument("--yes", action="store_true",
                   help="Non-interactive: accept all defaults (combine with --preset / --modules to override)")
    p.add_argument("--dry-run", action="store_true", help="Show what would be written and exit")
    p.add_argument("--no-backup", action="store_true", help="Don't back up existing files")
    p.add_argument("--force", action="store_true",
                   help="Overwrite existing files at the target without prompting. "
                        "Default behavior is to refuse if any would be clobbered "
                        "(except in --dry-run, where the warning is informational). "
                        "When --force is set, originals back up to *.bak-<ts> unless "
                        "--no-backup is also passed.")
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

    # --- apply CLI flags ---
    if args.preset:
        pmap = {"balanced": "Balanced (recommended)",
                "aggressive": "Aggressive (haiku-first, strict caps)",
                "relaxed": "Relaxed (correctness over cost)"}
        initial["formValues"]["efficiency_preset"] = pmap[args.preset]
        apply_preset(initial["formValues"])
    if args.modules:
        wanted = {m.strip() for m in args.modules.split(",") if m.strip()}
        initial["selected"] = wanted | {m["id"] for m in MODULES if m.get("required")}

    # --- interactive if needed ---
    if args.yes or args.config or args.preset or args.modules or args.save_config_only:
        config = initial
    else:
        config = interactive(target_dir, initial)

    # Resolve any declared module dependencies (e.g. commands-core -> agents)
    # before saving or scaffolding, so we never generate an inconsistent set.
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
    files, gitignore_lines = collect_files(config["formValues"], config["selected"])

    # Pre-flight: surface version mismatches, schema drift, heavy hooks,
    # and module prerequisites before writing any files.
    version_warnings = check_claude_code_version()
    if version_warnings:
        print()
        print(bold(yellow("[ VERSION WARNINGS ]")))
        for w in version_warnings:
            print(f"  {yellow('!')} {w}")

    merged = compute_merged_settings(config["formValues"], config["selected"])
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

    print()
    print(bold(blue("[ SUMMARY ]")))
    print(f"  Target : {green(str(target_dir))}")
    print(f"  Modules: {', '.join(sorted(config['selected']))}")
    print(f"  Files  : {len(files)} ({sum(1 for f in files if f['executable'])} executable)")
    if gitignore_lines:
        print(f"  .gitignore: append {sum(1 for l in gitignore_lines if l.strip() and not l.startswith('#'))} rules")

    # Retrofit safety (Tier 1): refuse to clobber existing project files
    # unless --force is passed. Dry-runs get the warning informationally
    # without exiting.
    collisions = check_retrofit_state(files, target_dir)
    if collisions:
        print()
        print(bold(yellow("[ RETROFIT WARNINGS ]")))
        print(f"  {yellow('!')} {len(collisions)} existing file(s) at target would be overwritten:")
        for target_rel, _ in collisions[:20]:
            print(f"    {yellow('!')} {target_rel}")
        if len(collisions) > 20:
            print(dim(f"    \u2026 and {len(collisions) - 20} more"))
        if not args.force and not args.dry_run:
            print()
            print(dim("  By default, cc-configure refuses to clobber existing project state."))
            print(dim("  Choose one:"))
            print(dim("    1. Re-run with --force to overwrite (originals back up to *.bak-<ts>)"))
            print(dim("    2. Re-run with --dry-run to see the full file list without writing"))
            print(dim("    3. Move/rename your existing files first if you want to merge manually"))
            print(dim("  Future tiers will add deep-merge for settings.json + .mcp.json and"))
            print(dim("  skip-and-stage for skill/agent/rule/hook collisions."))
            print()
            print(red("Aborted \u2014 no files written."))
            sys.exit(2)

    if args.dry_run:
        print()
        print(bold(yellow("[ DRY RUN \u2014 no files written ]")))
        for f in files:
            print(f"    {green('+')} {f['target']}")
        return

    print()
    result = apply_files(files, gitignore_lines, target_dir,
                        dry_run=False, backup=not args.no_backup)
    for p in result["written"]:
        print(f"    {green('wrote')} {p}")
    for p in result["backed_up"]:
        print(f"    {yellow('backed up')} {p}")
    if result["gitignore_added"]:
        print(f"    {green('+')} .gitignore (Claude Code block appended)")

    # Save config for re-runs
    save_config(config, saved_config_path)
    print(dim(f"    saved config to {saved_config_path.relative_to(target_dir)}"))

    print()
    print(green(bold("Done.")))
    print("Next steps:")
    print("  1. Review CLAUDE.md \u2014 populated from your answers.")
    print("  2. Review .claude/settings.json permissions.")
    print("  3. If .mcp.json was created, confirm enabled servers.")
    print("  4. Run: claude \u2014 then /memory and /context to check what loaded.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
        print("\033[31mAborted.\033[0m" if sys.stdout.isatty() else "Aborted.")
        sys.exit(130)
