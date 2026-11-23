---
paths: ["**/*.SemanticModel/**", "**/*.tmdl"]
---
# Power BI semantic models (TMDL)

TMDL is text meant for editing. Edit the files directly; do not round-trip through a tool that rewrites them.

## Layout
- One table per file under `definition/tables/`. A measure lives in its table's file. `model.tmdl` lists tables with `ref table`; `relationships.tmdl` holds relationships.
- Indentation is syntax: the depth of a line sets what it belongs to, and a wrong depth is a parse error that names the file and line. Keep the file's existing indentation (the parser accepts consistent tabs or consistent spaces).
- `definition.pbism` and `.platform` are not TMDL. Never change a `.platform` `logicalId`.

## After every edit
Run `./scripts/validate.sh models`. It parses the model with the Tabular Object Model's own TMDL parser, so it catches broken nesting, unknown keywords, relationships to columns that do not exist and duplicate names.

## What it does not check
**DAX and M are read verbatim.** Verified: unbalanced parentheses, an undefined function, a reference to a table that does not exist and circular measure dependencies all pass. A green result says the model is well-formed, not that it computes. So:
- Make DAX changes small and re-read them. Check every name against the model: a column that was renamed breaks its measures silently.
- Say in your summary which measures you changed and that they were **not machine-checked**.
- If a live engine is available (the Power BI Modeling MCP, or XMLA against a dev workspace), use it; otherwise leave that to the reviewer.

## Renames and removals
Update `SPEC.md` first. Then search for every consumer: other tables' DAX, relationships, roles, perspectives, calculation groups, and PBIR visuals in `*.Report/` that bind the field by name.

## Modelling
- No bidirectional filtering or many-to-many relationship without a reason recorded in `SPEC.md`.
- Keep names business-friendly in the model; the technical name belongs in the source column.
- A model that has `model.bim` (TMSL) instead of `definition/` is skipped by the offline parse. Say so rather than assuming it was checked.
