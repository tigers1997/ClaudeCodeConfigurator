# power-platform/

Source for Power Platform solutions: tables, canvas apps, cloud flows, environment variables and connection references. This folder is mostly **written by Microsoft tooling**, not by hand.

## Two layouts

`pac solution pack` reads a **pack root** and detects which layout it holds:

| Layout | A pack root contains | Written by |
|---|---|---|
| **YAML** | `solutions/<Name>/solution.yml`, `publishers/<Name>/publisher.yml`, component folders (`entities/`, `canvasapps/`, `modernflows/`, ...) | Power Platform **Git integration** (pac 2.4.1 or later packs it). Microsoft recommends it for new projects. |
| **XML** | `Other/Solution.xml`, `Other/Customizations.xml`, component folders | `pac solution unpack` (SolutionPackager) |

Use whichever your tooling writes, and do not mix them in one pack root. Put each solution in its own root (for example `power-platform/<SolutionName>/`): Microsoft documents `pac solution pack` for single-solution folders only.

`./scripts/validate.sh solution` finds every pack root under this folder and packs each one offline.

## What an agent may and may not do here

- **Do not hand-edit extracted solution files** except where Microsoft documents it. Change the solution in a development environment, then export or commit it again.
- **Canvas apps.** The `.pa.yaml` source is read-only outside Git integration (edits are ignored when the app loads); inside it only minor edits are supported, and not for apps that use code components. Never edit `.msapp` binaries.
- **Cloud flows** live under `modernflows/` in the YAML layout. Treat them as generated.
- **Environment-specific values** (URLs, connection IDs, secrets) must never be written into solution files: use environment variables, connection references and a deployment-settings file (`pac solution create-settings`).
- **Anything that reaches a tenant** (`pac auth`, `import`, `export`, `check`, `publish`) needs a human. They are `ask` permission rules, and the destructive ones are denied.

## What the offline check proves

`pac solution pack` proves the files are well-formed and packable. It does **not** prove the solution imports: "Pack success does not guarantee import success", and Microsoft's solution checker needs a tenant. The wrapper also fails when `pac` exits 0 but reports components that are not defined, because that is how `pac solution pack` reports missing files. See `docs/microsoft-data-stack.md`.
