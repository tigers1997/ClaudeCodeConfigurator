---
paths: ["power-platform/**"]
---
# Power Platform solutions

This folder is **written by Microsoft tooling** (Power Platform Git integration, or `pac solution unpack`). Treat it as generated.

## Do not hand-edit
- Microsoft documents hand-editing extracted solution files only in specific cases. For everything else: change the solution in a development environment, then export or commit it again.
- Canvas apps: the `.pa.yaml` source is read-only outside Git integration (edits are ignored when the app loads), and inside it only minor edits are supported, not for apps with code components. Never edit an `.msapp`.
- Cloud flows live under `modernflows/`. Do not hand-edit them.

## Environment-specific values
URLs, connection IDs, keys and tenant IDs never go into solution files. Use environment variables, connection references and a deployment-settings file (`pac solution create-settings`), and record them in `SPEC.md`.

## After a change
Run `./scripts/validate.sh solution`. It packs each pack root offline with `pac solution pack` and fails on a non-zero exit **and** on `pac` exiting 0 while reporting that components are not defined (that is how a missing component file shows up). Do not call `pac solution pack` directly and trust its exit code.

A clean pack is not a clean import: it does not run Microsoft's solution checker and does not touch a tenant.

## Live operations need a human
`pac auth`, `pac solution import | export | check | publish`, `pac admin` and the rest reach a tenant, so every `pac` call asks first, and `pac solution delete`, `pac admin delete | reset` and `pac auth token` are denied. Ask the user; never look for a way around the rule.

## Power Fx and flows (review points)
- Delegation: avoid patterns that pull a large data source into the app to filter it locally. Delegation warnings are visible in Power Apps Studio, not here.
- Flows: no per-item API calls inside `Apply to each` when a batch or filter query will do. Flows never bulk-copy data into Fabric; that is a pipeline's job.
