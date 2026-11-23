---
paths: ["fabric/**", "**/.platform", "**/notebook-content.py"]
---
# Fabric Git-integration items

## Identity
- An item is a folder `<displayName>.<Type>` holding a `.platform` file. The file's `config.logicalId` is the item's identity across workspaces. **Never change it.** An edit to a `.platform` is an `ask` permission rule.
- Copying an item folder? Give the copy a **new** `logicalId` (any new GUID) and a new `displayName`, or the next sync overwrites the original. `./scripts/validate.sh repo` fails when two items share one.
- `metadata.type` must match the folder's suffix (`Sales.SemanticModel` has type `SemanticModel`).

## What belongs in an item folder
- Only the item definition. Git integration deletes other files inside an item folder when it commits, so notes, scripts and tests go elsewhere.
- Paths stay under 250 characters and files under 25 MB.

## Notebooks (`notebook-content.py`)
- The file carries Fabric's own cell and metadata markers (`# CELL ****`, `# METADATA ****`). Edit the code inside a cell. Do not reorder, delete or reformat the marker lines, and do not run a formatter over the file: `ruff.toml` and `.prettierignore` already exclude it, so do not work around them.
- No secrets, workspace IDs, tenant IDs or URLs in a cell: read them from the environment, a Variable Library or a parameter.

## Environment-specific values
Anything that differs between Dev, Test and Prod is parameterised at deployment time (fabric-cicd `parameter.yml`; a Variable Library for the item types it supports, which does not include semantic models or reports). Never hard-code it. `./scripts/validate.sh repo` warns on the common URL shapes.

## Live operations need a human
`fab`, `az` and `pac` reach a tenant. They are `ask` rules; deleting (`fab rm`, `az ... delete`) is denied.
