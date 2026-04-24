# Worked examples

Each subdirectory here is a full `.claude/` output produced by running `cc-configure` against a specific stack. They're meant to answer the question *"what does this tool actually generate?"* without requiring you to install it first.

## Current examples

| Directory | Stack | Modules enabled |
|---|---|---|
| [`python-uv-fastapi/`](python-uv-fastapi/) | Python 3.12 + FastAPI (uv) | core, safety, git-workflow, token-efficiency, token-efficiency-pro, commands-core, agents |

More examples welcome — see [How to add one](#how-to-add-one) below.

## How these are generated

Each example lives in its own directory and is scaffolded the same way a real user would scaffold, except the inputs are captured in a committed `.claude-config.json` so the output is reproducible. To regenerate an example in place:

```bash
python3 configure.py \
    --config examples/<example-dir>/.claude-config.json \
    --dir   examples/<example-dir>
```

The stack/form answers come from the saved config; you just re-run it. If the templates have moved since the example was committed, the diff is how you catch drift.

## How to add one

1. Create a new subdirectory: `examples/<stack-slug>/`.
2. Build a config file that captures the stack preset + reasonable form answers:
   ```python
   # one-off at the repo root
   python3 - <<'PY'
   import json, sys; sys.path.insert(0, '.')
   from configure import default_form_values, default_selected, apply_stack_preset
   values = default_form_values()
   values['project_name'] = '<slug>'
   values['stack_preset'] = '<one of the STACK_PRESETS keys>'
   apply_stack_preset(values)
   # override any other fields as needed
   config = {'formValues': values, 'selected': sorted(default_selected()), '_version': 1}
   json.dump(config, open('examples/<slug>/.claude-config.json', 'w'), indent=2)
   PY
   ```
3. Run `cc-configure --config examples/<slug>/.claude-config.json --dir examples/<slug>`.
4. Add a per-example `EXAMPLE_README.md` describing the form inputs + a tour of key files.
5. Add a row to the table above.
6. Open a PR. CI will validate that `python3 configure.py --check` stays green (examples aren't scanned by `--check` today, but they get caught implicitly if they cause any static-template drift).

## Why they're committed

They're part of the test surface. If we change a template and forget to regenerate an example, the next contributor has a stale reference. A planned follow-up (Item 2 Phase 2 in `docs/07-backlog.md`) is a CI job that regenerates examples on each release tag and fails the build if they drift from current templates.
