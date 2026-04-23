# What's new in this update

Adds a **headless CLI** alongside the existing browser HTML so the configurator works on Debian / servers / CI — anywhere without a GUI.

## New files
- `configure.py` — the CLI. Stdlib-only, Python 3.8+. Interactive TUI by default; `--yes` / `--preset` / `--modules` for non-interactive runs.
- `config_schema.py` — shared source-of-truth for modules + form fields (now imported by both the HTML build and the CLI).
- `install.sh` — one-shot installer that clones, chmods, and symlinks `cc-configure` into `~/.local/bin`.

## Changed files
- `build/build_configurator.py` — refactored to import from `config_schema.py` and use relative paths (no more hardcoded dev paths).
- `README.md` — rewritten to put the headless flow first.
- `configurator.html` — regenerated from the shared schema (same functionality; slight size decrease).

## How to use on Debian

```bash
curl -sL https://raw.githubusercontent.com/tigers1997/ClaudeCodeConfigurator/main/install.sh | bash
cd your-project
cc-configure
```

First run is interactive (prompts with sensible defaults). `.claude-config.json` is saved in the project directory for subsequent re-runs.
