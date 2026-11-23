#!/usr/bin/env python3
"""Write a .claude-config.json for the codex-cli tests.

usage: _make-config.py OUT [key=value ...]   (run from the repo root)

  provider=openai|azure   holdout_ci=0|1   cross_review=0|1
  review_model=NAME   bulk_model=NAME   effort=low|medium|high

The solo-experienced persona plus the codex harness (and its agents-md
dependency) is the base; the flags land in module_flags["codex-cli"].
"""
import json
import sys

sys.path.insert(0, ".")
import configure  # noqa: E402

out, pairs = sys.argv[1], dict(a.split("=", 1) for a in sys.argv[2:])
fv = configure.default_form_values()
for key, field in (("provider", "codex_provider"), ("review_model", "codex_review_model"),
                   ("bulk_model", "codex_bulk_model"), ("effort", "codex_review_effort")):
    if key in pairs:
        fv[field] = pairs[key]
flags = {}
for key in ("holdout_ci", "cross_review"):
    if key in pairs:
        flags[key] = pairs[key] == "1"
mods, pflags = configure.pick_persona_modules("solo-experienced")
selected = sorted(configure.resolve_dependencies(set(mods) | {"codex-cli"}))
module_flags = {k: dict(v) for k, v in pflags.items()}
module_flags["codex-cli"] = flags
with open(out, "w", encoding="utf-8") as fh:
    json.dump({"schema_version": 2, "persona": "solo-experienced", "module_flags": module_flags,
               "formValues": fv, "selected": selected}, fh)
