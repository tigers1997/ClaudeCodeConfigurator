# Stack types

A **stack preset** prefills the intake answers for a language and toolchain: `Python (uv)` sets `cmd_test` to `uv run pytest`, and so on. A **stack type** goes further. It is a preset that also installs files, because the project is not an application in one language: here, the whole repository is Microsoft Fabric, Power BI and Power Platform source, and it needs its own validators, path-scoped rules, permissions and review checklist.

The mechanism is generic. The one stack type shipped so far is `microsoft-data` ([how it works](../templates/stack-microsoft-data/docs/microsoft-data-stack.md) once scaffolded; it is written into the project as `docs/microsoft-data-stack.md`). This page is for someone adding the next one.

## Choosing one

```bash
cc-configure --persona solo-experienced --yes --stack microsoft-data
cc-configure --stack python-uv         # a plain preset: values only, no module
```

`--stack` takes a slug (`node-ts`, `node-js`, `python-uv`, `python-poetry`, `python-pip`, `go`, `rust`, `microsoft-data`, `custom`) or the full preset name, case-insensitively. In quick mode it is question 3; `--stack` answers it, so it is not asked. Choosing a stack that carries a module turns the module on; choosing any other preset turns it off again and leaves shared infrastructure (`agents-md`) alone, since you may have picked that as a harness in its own right ([doc 12](12-multi-harness.md)).

## The four parts of a stack type

| Part | Where | What it does |
|---|---|---|
| **Preset** | `STACK_PRESETS` in `config_schema.py` | Prefills form values: language, commands, design and style answers. |
| **Extras** | `STACK_PRESET_EXTRAS` | Names the modules the preset turns on, and a `review_rules` fragment. `STACK_MODULES` in `configure.py` is derived from it, so a module listed here belongs to that one preset. |
| **Slug** | `STACK_SLUGS` | The `--stack` spelling. |
| **Module** | `MODULES`, files under `templates/stack-<slug>/` | The files: scripts, rules, docs, a settings patch, `.gitignore` and `.gitattributes` lines, an optional workflow. Declare `dependsOn: ["agents-md"]` so the review rules have somewhere to land. |

`python3 configure.py --check` verifies the registry: every extras key is a real preset, every module exists, every `review_rules` fragment exists, and every slug names a preset.

## Things that are easy to get wrong

- **The Stop hook runs your commands every turn.** `cmd_typecheck`, `cmd_lint` and `cmd_test` become the three checks of `stop-run-checks.sh`. It guards a command only when its first word is a package manager it knows (`manifest_for`); a repo script such as `./scripts/validate.sh` runs unguarded. So the script must be **silent when nothing relevant changed** (`--changed`), must exit non-zero only when a tool ran and found a problem, and must not fail because a tool is absent.
- **Skip is not pass, and missing is not failure.** `validate.sh` prints `SKIP` for a tier whose tool is not installed and `FAIL` for one that ran and found something; `--strict` turns every skip into a failure, and CI uses it so a runner without .NET cannot go green having validated nothing. A tool that ran but printed no verdict (no network for `npx`) is a skip, not a pass.
- **Read the tool's output, not only its exit code.** `pac solution pack` exits 0 when it leaves components out. The wrapper fails on the message. Whenever you wrap a tool, break an input on purpose and see what it actually prints.
- **Select fields only accept their own options.** `prompt_select` resets a value that is not among a plain select's options, so a preset may set free-text and `allow_custom` fields only. `test-stack-selection.sh` enforces it.
- **The `language` answer drives plugin recommendations.** `compute_recommended_plugins` keys off words like `python`. The Microsoft preset says `PySpark` so that it does not get Python-application suggestions that do not apply.
- **Override the web-app defaults.** Design answers such as the auth and state-management lines default to NextAuth and React state. In a stack where they are false they actively mislead an agent, so the preset replaces them.
- **Files the repository may already own.** A stack module that writes a shared config file (`ruff.toml`, `.prettierignore`, `.config/dotnet-tools.json`) meets the user's own copy in a retrofit: the default collision strategy keeps theirs and stages yours, so the lines your stack depends on can silently be missing. Add a check to the warnings block of `configure.py` (`check_stack_microsoft_config` is the example) that fires only when an existing file lacks those lines, so it stays quiet on a fresh target and on a re-run, and record it in the retrofit report. Also check what your file *shadows*: ruff reads one config file, and `ruff.toml` outranks `[tool.ruff]` in `pyproject.toml`.
- **Never pre-approve a command that reaches a tenant or an account.** The settings patch allows the offline validators and puts everything live under `ask` or `deny`. Nothing third-party is vendored; pin versions, and never accept a licence on the user's behalf.
- **Say what is not validated.** The generated doc has a table of what each tier proves and what it cannot (for Microsoft: nothing offline checks DAX or M), with an access date on every source.

## Checklist

1. Add the preset to `STACK_PRESETS`, its `STACK_SLUGS` entry, and a `STACK_PRESET_EXTRAS` entry.
2. Add the module to `MODULES` and its templates under `templates/stack-<slug>/`. A `{{stack_review_rules}}` fragment continues the numbered list in `AGENTS.md` under its own `###` heading (the slot is empty without the module, and the file is then byte-identical to one without the feature).
3. Add a `target_path_for` rule only if you introduce a new `dot-` prefixed directory (`dot-claude`, `dot-github` and `dot-config` exist).
4. Write the validators as scripts the project owns, with a stub-based test that pins the wrapper's logic (tier selection, skip versus fail versus strict, each tool's real messages) and a real-tool test that skips when the tool is absent. Put the real-tool test in its own CI job, as `microsoft-data-real-tools` does: it depends on package registries, so it must not be a required check.
5. Commit a small real fixture, run every validator against it, then break it in each way you claim to catch and confirm the failure. Pin in a test the things you found that the tools do **not** catch.
6. Add `examples/stack-<slug>/` (a saved `.claude-config.json` and `expected-tree.txt`) and a snapshot step in `.github/workflows/check.yml`, a smoke-loop entry, and a CHANGELOG entry that states what was and was not verified.
7. Regenerate the index: `python3 configure.py --write-index`.

## Not built yet

Further stack types (data engineering, infrastructure as code), and the other harness adapters listed in [doc 12](12-multi-harness.md).
