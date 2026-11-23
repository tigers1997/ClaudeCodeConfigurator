### Fabric, Power BI and Power Platform

6. **Contract drift:** names of tables, columns, measures, environment variables, connection references and flows match `SPEC.md`. A rename updated `SPEC.md` first and then every consumer (DAX, relationships, report visuals, flows, apps).
7. **ALM:** no tenant IDs, workspace GUIDs, environment or Dataverse URLs, connection IDs or credentials in the diff. Environment-specific values come from environment variables, connection references, deployment settings or a Variable Library.
8. **Identity files:** a `.platform` `logicalId` is unchanged (a copied item folder has a new `logicalId` and a new `displayName`), nothing extra lives inside an item folder, and notebook cell and metadata markers are intact.
9. **Model integrity:** TMDL keeps its nesting and one-table-per-file layout. Look for circular measure dependencies, bidirectional relationships without a reason recorded in `SPEC.md`, and DAX that still references something the diff renamed or removed. The offline checks do not validate DAX or M, so this review is the only check on them.
10. **Report bindings:** every field a PBIR visual references still exists in the model after the change.
11. **Power Platform:** solution files are generated, not hand-edited. Power Fx avoids non-delegable patterns on large data sources, and flows avoid per-item API calls inside `Apply to each`.
