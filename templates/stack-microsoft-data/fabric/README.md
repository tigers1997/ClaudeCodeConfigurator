# fabric/

The root of this repository's Microsoft Fabric Git-integration folder. Everything here is source for Fabric items: semantic models, reports, notebooks and the rest.

## Layout

```
fabric/
  Sales.SemanticModel/      <displayName>.<Type>, one folder per item
    .platform               the item's identity (see below)
    definition.pbism
    definition/             TMDL: database.tmdl, model.tmdl, relationships.tmdl, tables/*.tmdl
  Sales.Report/
    .platform
    definition.pbir         points at the model with a relative path (byPath)
    definition/             PBIR: report.json, version.json, pages/<page>/page.json, ...
  Etl.Notebook/
    .platform
    notebook-content.py
```

Items may sit in subfolders. A folder is an item only if it contains a `.platform` file.

## Rules that are easy to break

- **`.platform` is the item's identity.** Git integration matches items across workspaces by `config.logicalId`. Never edit it. A copied item folder needs a **new** `logicalId` and a new `displayName`, or it overwrites the original on the next sync.
- **Keep other files out of item folders.** On commit, Git integration deletes files inside an item folder that are not part of the item definition. Put notes and scripts elsewhere.
- **Do not commit** `**/.pbi/localSettings.json` or `**/.pbi/cache.abf` (they are ignored), or a `.pbix`: a binary cannot be reviewed or merged, and PBIP is the source format.
- **No environment coordinates in source**: tenant IDs, workspace GUIDs, workspace URLs. Parameterise them at deployment time (for example with fabric-cicd's `parameter.yml`, or a Variable Library for the item types it supports).

## Checking your work

`./scripts/validate.sh` checks the identity files, parses every TMDL model and validates every PBIR report. It does not validate DAX or M. See `docs/microsoft-data-stack.md`, and `SPEC.md` for the names these items must agree on.
