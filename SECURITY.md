# Security policy

## Reporting a vulnerability

If you find a security issue in ClaudeCodeConfigurator, please email **brougeaux@yahoo.com** with subject `[security] ClaudeCodeConfigurator` rather than filing a public GitHub issue. Include:

- A description of the problem
- Steps to reproduce
- What an attacker could achieve

I aim to acknowledge within 7 days. Coordinated disclosure is appreciated — I'll confirm a timeline for the fix before any public discussion.

For non-security bugs and feature requests, please open a regular [issue](../../issues).

## Scope

The configurator writes scaffolding files to a user-chosen directory. In-scope vulnerabilities:

- **Path traversal** in `configure.py` that could write outside the target directory regardless of `--dir`.
- **Template injection** via intake-form values (goals, instructions, etc.) that could lead to arbitrary file writes or command execution during scaffolding.
- **Hooks in `templates/`** that could be tricked into executing untrusted input when a scaffolded project runs them.
- **Install script** (`install.sh`) writing to paths outside `$HOME/.cc-configurator` and `$HOME/.local/bin` without warning.

## Out of scope

- Behavior when the user intentionally passes `--no-backup` (acknowledged tradeoff — backup is on by default).
- Running the tool with elevated privileges or in a path owned by another user.
- Upstream Claude Code behavior (report those to Anthropic).
- Supply-chain risk from piping `install.sh` to `bash` — users accepting that pattern accept the attendant risk. Mitigation: clone the repo first, read the script, then run it.

## What this tool does *not* do

- Does not make network calls during scaffolding.
- Does not read files outside the target directory.
- Does not collect telemetry.
- Has no runtime dependencies beyond the Python 3 standard library.
