---
paths: ["**/*.Report/**"]
---
# Power BI reports (PBIR)

A PBIR report is a folder of small JSON files, designed to be edited as text.

## Rules
- Every JSON file under the report has a `$schema`; Fabric rejects PBIR definition files without one. Keep it, and keep the schema version the file already uses.
- UTF-8 **without** a BOM. Names of pages and visuals use word characters or hyphens only.
- Do not touch `mobileState.json`, `semanticModelDiagramLayout.json` or `diagramLayout.json`, and do not edit a legacy `report.json` (a report in the old format is converted by Power BI Desktop when it is saved, not by hand).
- `definition.pbir` points at the semantic model with a relative `byPath` and must keep doing so while the model is in this repository: fabric-cicd rewrites it at deployment time and fails if the model is not in the repo.
- Never change a `.platform` `logicalId`.

## After every edit
Run `./scripts/validate.sh report`. It validates every file against Microsoft's PBIR JSON schemas and checks the structure: invalid JSON, a missing `$schema`, a wrong type or enum, an unknown property, a `pageOrder` that names a page that does not exist, a missing `.platform` or `definition.pbir`, a BOM.

## What it does not check
**It does not check that a visual's field bindings exist in the model.** After renaming or removing anything in the model, search the report for the old name yourself, and make sure `SPEC.md` agrees. Say in your summary that bindings were not machine-checked.
