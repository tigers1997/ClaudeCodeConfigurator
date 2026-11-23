# Microsoft data & BI stack

How this repository is set up for Microsoft Fabric, Power BI and Power Platform work done by coding agents, and **exactly what its checks prove and do not prove**. Verified 2026-11-23 on Linux x64 with .NET SDK 10.0.404, `Microsoft.AnalysisServices` 19.120.1, `pac` 2.16.1 and `@microsoft/powerbi-report-authoring-cli` 0.5.0. These tools move fast; re-run `./scripts/validate.sh` after upgrading any of them.

## What was added

| Path | Purpose |
|---|---|
| `SPEC.md` | The contract between the layers. Update it **first** when you rename or remove anything. |
| `fabric/`, `power-platform/` | Layout notes for the two source roots. |
| `.claude/rules/` | Four path-scoped rules saying what an agent may edit (TMDL, PBIR, Fabric items, Power Platform). |
| `scripts/validate.sh` | The tiered offline checks below. `--changed` keeps the Stop hook fast; `--strict` makes CI fail on a skipped tier. |
| `scripts/tmdl-check.cs`, `scripts/check_fabric_items.py`, `scripts/report_diagnostics.py` | The TMDL parse (a .NET 10 file-based app) and the stdlib identity and diagnostics helpers. |
| `.config/dotnet-tools.json` | Pins `pac` (`dotnet tool restore`). |
| `ruff.toml`, `.prettierignore` | Keep the format-on-write hook away from Fabric notebooks and Microsoft-written sources. |
| `.github/workflows/validate.yml` | The same checks in CI (option `ci_validate`). |
| `.claude/settings.json` | Offline validators allowed; every `pac`, `fab` and `az` call asks; destructive ones are denied. |

## The validation tiers

| Tier | Runs | Needs | Catches (verified) | Does **not** catch (verified) |
|---|---|---|---|---|
| `repo` | `.platform` identity and hygiene checks | `python3` | invalid or incomplete `.platform`, a folder suffix that does not match `metadata.type`, a duplicated `logicalId` (a copied item), a folder that looks like an item but has no `.platform`, tracked `.pbi` cache files | whether an item's contents are valid |
| `models` | TOM `TmdlSerializer` over each `*.SemanticModel/definition` | .NET 10 SDK | wrong nesting, unknown keywords, relationships to a missing column, a `ref table` with no file, duplicate objects, a missing folder | **broken DAX** (unbalanced parentheses, undefined function), a reference to a table that does not exist, **circular measure dependencies**, M errors |
| `report` | `powerbi-report-author validate` over each `*.Report` | Node 20+ | invalid JSON, a missing `$schema`, schema violations (bad enum, wrong type, unknown property), a `pageOrder` that names a missing page, a missing `.platform` or `definition.pbir`, a BOM | whether a visual's fields exist in the model |
| `solution` | `pac solution pack` over each pack root, offline | `pac` | malformed XML, missing required files, **components whose files are missing** | whether the solution **imports**; the solution checker needs a tenant |
| `python` | `ruff check`, `pytest` | `uv`, or `ruff`/`pytest` on PATH | what those tools catch | |

**Nothing offline validates DAX or M.** Tabular Editor's `Measure.ErrorMessage` is set by an engine, so a model loaded from files fails open; fabric-cicd has no dry-run and no TMDL parser; `pac solution pack` only packages. The honest options for DAX are a reviewer (see Code Review Rules in `AGENTS.md`) and a live engine: the Power BI Modeling MCP or XMLA against a development workspace.

**`pac solution pack` exits 0 when a component's files are missing.** With pac 2.16.1 it prints `Following root components are not defined in customizations:` (no "warning" label), writes a zip and returns 0. `validate.sh` fails on that message and on the generic words (`error`, `cannot find`, `could not`, ...), so do not call `pac solution pack` and trust its exit code. The YAML layout is documented to behave the same way for components declared in `rootcomponents.yml`; that path was not exercised here because a valid YAML-layout solution could not be produced without Power Platform Git integration, only detection and the missing-required-file error were.

## Tools

| Tool | Install | Notes |
|---|---|---|
| .NET 10 SDK | dot.net, or your package manager | Required for the TMDL parse (`dotnet run` on a `.cs` file). The first run restores NuGet and takes about 20 s; later runs take well under a second. |
| `pac` | `dotnet tool restore` (pinned to 2.16.1 in `.config/dotnet-tools.json`) | `pac data` and `pac package deploy` are Windows-only. |
| Node 20+ | nodejs.org | `validate.sh` runs `npx` with the exact version pinned in the script and install scripts disabled (`npm_config_ignore_scripts=true`), because the package is a public preview that pulls in dependencies. Install `powerbi-report-author` yourself to skip the fetch. |
| `uv` | astral.sh/uv | Only for the `python` tier. |

`validate.sh` needs `bash` (Git Bash on Windows). It sets `DOTNET_CLI_TELEMETRY_OPTOUT=1` for the runs it starts.

## Running it

```bash
./scripts/validate.sh                       # every tier that applies
./scripts/validate.sh models report         # just those
./scripts/validate.sh --changed             # only tiers whose files changed (silent if none)
./scripts/validate.sh --strict              # a SKIP fails: use in CI
```

The Stop hook runs it through the `cmd_typecheck`, `cmd_lint` and `cmd_test` answers with `--changed`, and reports a failure back to Claude once. A SKIP is printed, never counted as a pass.

## Adding this to a repository that already has config

Three of the files above are ones a repository often owns already. `cc-configure` keeps yours by default and stages the stack's copy in `.claude-retrofit/incoming/`, and it warns when yours lacks what the stack needs:

| File | What the stack needs in it | If it is missing |
|---|---|---|
| `ruff.toml` | `force-exclude = true` and `extend-exclude = ["fabric/**/notebook-content.py"]` | the format-on-write hook rewrites Fabric notebooks |
| `.prettierignore` | `fabric/` and `power-platform/` | the hook reformats sources that Fabric and `pac` own |
| `.config/dotnet-tools.json` | the pinned `microsoft.powerapps.cli.tool` entry | `./scripts/validate.sh solution` is skipped unless `pac` is on PATH |

A `ruff.toml` also **outranks** `[tool.ruff]` in `pyproject.toml`: ruff reads one configuration file, not both. If your settings live in `pyproject.toml`, make `extend = "pyproject.toml"` the first line of `ruff.toml` (it keeps your settings and the stack's exclusions; ruff fails if `pyproject.toml` is later removed). A `.ruff.toml` outranks `ruff.toml` in the same way.

## What needs a human

Anything that reaches a tenant: `pac auth | org | admin | solution import | export | check | publish`, `fab`, `az`. All are `ask` rules; `pac solution delete`, `pac admin delete | reset`, `pac auth token` (it prints an access token) and `fab rm` are denied. Deployment (fabric-cicd, `microsoft/powerplatform-actions`, OIDC federated credentials) is not generated: it is tenant-specific, and the safe shape is documented by Microsoft. Fabric's guidance favours a release commit or tag deployed to Test and Prod with fabric-cicd, with only Dev connected to Git; Power Platform's favours Git integration in development environments only, building artifacts and deploying through pipelines. Keep environment values in environment variables, connection references and deployment settings.

## MCP servers (optional, need the `mcp` module)

| Server | Option | Notes |
|---|---|---|
| Microsoft Learn | `mcp_ms_learn` (on for this stack) | Remote, no auth. Current Microsoft docs: the APIs here change often. |
| Azure | `mcp_azure` | `@azure/mcp` 3.0.0, started `--read-only`, uses your `az login`. Node 22+. |
| Fabric | `mcp_fabric` | `@microsoft/fabric-mcp` 1.8.0, started `--read-only`. Node 22+. Maturity is not labelled consistently. |
| Power BI Modeling | `mcp_powerbi_modeling` | `@microsoft/powerbi-modeling-mcp` 1.0.1. **Can edit models.** Linux and Windows only (no macOS). You must accept its EULA yourself; the scaffold never passes `--accept-eula`. |

The Dataverse MCP needs a per-organisation URL and tenant admin consent, so it is not generated.

## Microsoft's own agent skills (optional)

Microsoft publishes skills for these stacks. They are referenced here, not copied. Several send telemetry by default (each plugin documents its opt-out), so read before installing:

- `microsoft/skills-for-fabric`: `/plugin marketplace add microsoft/skills-for-fabric`, then `/plugin install powerbi-authoring@fabric-collection`
- `microsoft/power-platform-skills`: `/plugin marketplace add microsoft/power-platform-skills`, then `/plugin install <name>@power-platform-skills`
- `azure@claude-plugins-official`, and `microsoft/Dataverse-skills` (needs a live environment)

## Known gaps

- No offline DAX, M or circular-dependency check. Tabular Editor's new `te` CLI (`te validate`, `te bpa run`) is a login-gated preview whose licence ends 2026-12-31 and cannot be redistributed, so it is not shipped.
- The YAML-layout pack path was not exercised against a real YAML solution (see above).
- Fabric notebook marker syntax is documented only as a screenshot, so notebooks are protected from formatters rather than parsed.
- Whether `pac solution check` needs only a tenant or a Dataverse environment is not documented.

## Sources (checked 2026-11-23)

learn.microsoft.com: power-bi/developer/projects, analysis-services/tmdl, fabric/cicd (git-integration, manage-deployment, variable-library), power-platform/alm (solution-source-control-yaml-format, git-integration, solution-packager-tool), power-platform/developer/cli. github.com/microsoft/fabric-cicd, microsoft/skills-for-fabric, microsoft/power-platform-skills, microsoft/json-schemas. docs.tabulareditor.com/en/features/te-cli. npm: `@microsoft/powerbi-report-authoring-cli`, `@azure/mcp`, `@microsoft/fabric-mcp`, `@microsoft/powerbi-modeling-mcp`. NuGet: `Microsoft.AnalysisServices`, `Microsoft.PowerApps.CLI.Tool`.
